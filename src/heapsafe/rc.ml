(* Copyright (c) 2007 Intel Corporation 
 * All rights reserved. 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 * 
 * 	Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 * 	Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *     Neither the name of the Intel Corporation nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 * PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE INTEL OR ITS
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *)
(* Main file for generating reference counting code 
   Comments:
     - we can do better on local structs whose address is not taken
 *)

open Cil
open Rcutils
open Rclocals
open Rcinit
open Dcheckdef

module DU = Dutil
module L = List
module E = Errormsg
module H = Hashtbl
module S = String

module UD = Usedef
module VS = UD.VS

(* 'adjustFunctions' maps the varinfo of "rc_adjust..." functions we know 
   about to true *)
let adjustFunctions = H.create 32 

(* Those rc_adjust... functions which we will automatically generate *)
let autoGeneratedAdjustFunctions = H.create 32

(* 'adjustFunctionsToAdd' is a map from a function F to the 
   automatically generated adjust functions that it uses - these
   must be printed before F *)
let adjustFunctionsToAdd = H.create 32

exception NoRcPointers

let rec typeName t = match t with
    | TPtr (ti, _) -> "ptr_" ^ typeName ti
    | TComp (ci, _) -> ci.cname
    | TEnum (ei, _) -> "enum_" ^ ei.ename
    | TArray (ta,_,_) -> typeName ta
    | TNamed (ti,_) -> typeName ti.ttype
    | TVoid _ -> "void"
    | TFloat (FFloat, _) -> "float"
    | TFloat (FDouble, _) -> "double"
    | TFloat (FLongDouble, _) -> "long_double"
    | TInt (IChar, _) -> "char"
    | TInt (ISChar, _) -> "char_s"
    | TInt (IUChar, _) -> "char_u"
    | TInt (IInt, _) -> "int"
    | TInt (IUInt, _) -> "int_u"
    | TInt (IShort, _) -> "short"
    | TInt (IUShort, _) -> "short_u"
    | TInt (ILong, _) -> "long"
    | TInt (IULong, _) -> "long_u"
    | TInt (ILongLong, _) -> "long_long"
    | TInt (IULongLong, _) -> "long_long_u"
    | _ -> "void"

(* RCHACK: in debug mode all non-ptr types are treated as word-size integers *)

(* Return the varinfo representing the definition of the "rc_adjust..."
   function for type 't'. The use of this adjust function is in function
   'inGlob' of file 'fi' at location 'loc'.
   Arrange for the "rc_adjust..." function to be generated just before 'inGlob'
   if it is not yet known, and it is possible to generate it (report an
   error if not). 
   Throw exception NoRcPointers if type 't' contains no reference counted
   pointers.
*)
let rcAdjustForType (fi:file) (inGlob:varinfo) (t:typ) (loc:location) : varinfo =
  let rec baseType t =
    match t with
    | TPtr (ti,_) -> ("ptr_" ^ typeName ti, "void *", t)
    | TComp (ci, _) when typeContainsCountedPointers t -> 
                (ci.cname, compFullName ci, t)
    | TArray (ta, _, _) -> baseType ta
    | TNamed (ti, _) -> baseType ti.ttype
    | TInt (_,_) | TFloat (_,_) | TEnum (_,_) 
                when !Ivyoptions.typeDebug -> 
                        ("rcbasic", "nonptr type", TInt(IUInt,[]))
    | TInt (IChar, _) ->
	if !Ivyoptions.warnTypeofChar then
	  ignore(warnLoc loc "type of 'char' requested");
	raise NoRcPointers
    | _ -> raise NoRcPointers in 
  let (basename, nicename, t') = baseType t in
  let name = "rc_adjust_" ^ basename in
  let (vi, isNew) = findFunction fi name rcTypes.rc_adjust in
  if not (H.mem adjustFunctions vi) then
    (* We're seeing this "rc_adjust..." function for the first time *)
    if isNew then
      begin
	H.add adjustFunctions vi true;
	H.add autoGeneratedAdjustFunctions name true;
	(* If the user declared no "rc_adjust..." function, try to generate
	   one just before 'inGlob' (see rcprint.ml for details) *)
	if typeContainsUnionWithCountedPointers t' then begin
	  let msgLoc = if !Ivyoptions.fakeAdjust then warnLoc else errorLoc in
          ignore(msgLoc loc "need handwritten rc_adjust function for %s called %s" nicename name)
	end;
	vi.vstorage <- Static; (* Generated rc_adjust functions are static *)
      end
    else
      begin
	(* Add a prototype for vi to the start of the file - it may
	   be declared after inGlob. We make a new fake varinfo because
	   the actual one may refer to typedefs (especially size_t) *)
	let fakeVi = makeGlobalVar name rcTypes.rc_adjust in
	fakeVi.vstorage <- vi.vstorage;
	declareEarly fi fakeVi;
	H.add adjustFunctions fakeVi true
      end;
  (* Remember the auto-generated rc_adjust functions needed by inGlob *)
  if H.mem autoGeneratedAdjustFunctions name then
    H.add adjustFunctionsToAdd inGlob (name, t');
  vi

(* Conservative equality for lvalues & co *)

let rec expeqc (e1:exp) (e2:exp) : bool = 
  match (e1, e2) with
  | (Lval lv1, Lval lv2) -> lvaleqc lv1 lv2
  | (Const c1, Const c2) -> c1 = c2
  | (AddrOf lv1, AddrOf lv2) -> lvaleqc lv1 lv2
  | (StartOf lv1, StartOf lv2) -> lvaleqc lv1 lv2
  | (UnOp (u1, e1, _), UnOp (u2, e2, _)) -> u1 = u2 && (expeqc e1 e2)
  | (BinOp (b1, e1a, e1b, _), BinOp (b2, e2a, e2b, _)) ->
      b1 = b2 && (expeqc e1a e2a) && (expeqc e1b e2b)
  | _ -> false

and compeq (c1:compinfo) (c2:compinfo) : bool = c1.cname = c2.cname

and fieldeq (f1:fieldinfo) (f2:fieldinfo) : bool = 
  (compeq f1.fcomp f2.fcomp) && f1.fname = f2.fname

and offseteqc (o1:offset) (o2:offset) : bool = 
  match (o1, o2) with
  | (NoOffset, NoOffset) -> true
  | ( (Field (f1, o1)), (Field (f2, o2)) ) -> (fieldeq f1 f2) && (offseteqc o1 o2)
  | ( (Index (i1, o1)), (Index (i2, o2)) ) -> (expeqc i1 i2) && (offseteqc o1 o2)
  | _ -> false

and lhosteqc (lh1:lhost) (lh2:lhost) : bool = 
    match (lh1, lh2) with
  | (Var v1, Var v2) -> v1.vname = v2.vname
  | (Mem m1, Mem m2) -> expeqc m1 m2
  | _ -> false

and lvaleqc ((lh1, o1):lval) ((lh2, o2):lval) : bool = 
  (lhosteqc lh1 lh2) && (offseteqc o1 o2)


let rec offsetting (var:lval) (newval:exp) = 
  (* Don't optimise += when using the debug library *)
  not !Ivyoptions.hsdebug &&
  match newval with
  | BinOp(PlusPI, ptr, _, _) -> offsetting var ptr
  | BinOp(IndexPI, ptr, _, _) -> offsetting var ptr
  | BinOp(MinusPI, ptr, _, _) -> offsetting var ptr
  | Lval lv -> lvaleqc lv var
  | CastE(_, e) -> offsetting var e
  | _ -> false

(* Generate a call to the "rc_adjust..." function for lvalue 'lv', adjusting
   the reference count by 'by' *)
let rcAdjustSize (fi:file) (inFn:fundec) (lv:lval) (by:int) (size:exp) (loc:location) : instr = 
  let adjustor = rcAdjustForType fi inFn.svar (typeOfLval lv) loc in
  Call(None, (v2e rcFunctions.rcadjust), 
       [v2e adjustor; mkAddrOf lv; integer by; size], loc)

(* Generate a call to the "rc_adjust..." function for lvalue 'lv', adjusting
   the reference count by 'by' *)
let rcAdjust (fi:file) (inFn:fundec) (lv:lval) (by:int) (loc:location) : instr = 
  rcAdjustSize fi inFn lv by zero loc

let rec isBitfield offset = match offset with
    | Field({fbitfield = None; fname=name},offset) -> isBitfield offset
    | Field(_,offset) -> true
    | Index(_,offset) -> isBitfield offset
    | _ -> false
  
let tempVar (vi:varinfo) = 
  let n = vi.vname in
  try
    S.sub n 0 3 = "__d"
  with Invalid_argument _ -> false

let nonTemps (vl:varinfo list) = 
  L.filter (fun vi -> not (tempVar vi)) vl

(* Wrap all assignments (except those to variables in 'oVars') with 
   reference count operations (i.e., calls to the appropriate
   "rc_adjust..." function. *)
class rcAssignments (fi:file) (oVars:varinfo list) : cilVisitor = 
  object (self)
    inherit nopCilVisitor as super

    val currentFn : fundec ref = ref dummyFunDec;
    method vfunc (f:fundec) =
      currentFn := f;
      DoChildren


    method vinst (i:instr) =
      let needsRefCount lv = match lv with
      | Var vi, NoOffset when L.memq vi oVars || tempVar vi -> false
      | _ when typeContainsCountedPointers (typeOfLval lv) -> true
      | _ when !Ivyoptions.typeDebug -> true
      | _ -> false
      in
    
      match i with
      | Set((_, offset), _, _) when isBitfield offset -> DoChildren
      | Set(lv, value, loc) when needsRefCount lv(* && not (offsetting lv value) *) -> 
	    if (isZero value) then
              ChangeTo [
                rcAdjust fi !currentFn lv (-1) loc; 
                i ]
	    else
              ChangeTo [
                rcAdjust fi !currentFn lv (-1) loc; 
                i; 
                rcAdjust fi !currentFn lv 1 loc ]
      | Call(Some lv, func, args, loc) when needsRefCount lv -> 
            let tmp = makeTempVar !currentFn ~name:"ctmp" (typeOfLval lv) in
            let tmplv = Var tmp, NoOffset in
            ChangeTo [ 
                Call (Some tmplv, func, args, loc);
                rcAdjust fi !currentFn lv (-1) loc;
                Set (lv,Lval tmplv,loc);
                rcAdjust fi !currentFn lv 1 loc ]
      | _ -> DoChildren
  end

(* Refcount on entry to 'f' all variables in 'aParms' (the parameters
   that are not optimised) *)
let rcOnEntry (fi:file) (f:fundec) (aParms:varinfo list) (loc:location) : unit = 
  let incRc vi = [ rcAdjust fi f (Var vi, NoOffset) 1 loc ] in
  let incInstrs = L.concat (L.map incRc aParms) in
  let incStmt = mkStmt (Instr incInstrs) in
  f.sbody.bstmts <- [ incStmt ] @ f.sbody.bstmts

(* Generate a call to __builtin_ipush/ipop for variable 'vi' at 
   location 'loc' in function 'f' of file 'fi' *)
let iPushPopCall (push:varinfo) (fi:file) (f:fundec) (vi:varinfo) (loc:location) : instr =
  let typeVi = rcAdjustForType fi f.svar vi.vtype loc in
  let var = mkAddrOf (Var vi, NoOffset) in
  Call(None, (v2e push), [ var; (v2e typeVi); SizeOfE (v2e vi) ], loc)

(* On entry to 'f' in file 'fi', push to the parallel stack the variables in 
   'uVars' *)
let pushOnEntry (fi:file) (f:fundec) (uVars:varinfo list) (loc:location) : unit = 
  let push vi = [ iPushPopCall rcFunctions.ipush fi f vi loc ] in
  let pushInstrs = L.concat (L.map push (nonTemps uVars)) in
  let pushStmt = mkStmt (Instr pushInstrs) in
  f.sbody.bstmts <- [ pushStmt ] @ f.sbody.bstmts

(* On exit, dereference and pop from parallel stack all locals in 'vars' *)
class rcOnExit (fi:file) (vars:varinfo list) : cilVisitor = 
  object (self)
    inherit nopCilVisitor as super

    val currentFn : fundec ref = ref dummyFunDec;
    method vfunc (f:fundec) =
      currentFn := f;
      DoChildren

    method vstmt (s:stmt) = 
      begin
        match s.skind with
        | Return(_, loc) -> 
	    (* Add calls to "__builtin_ipop" just before the return
	       (the dereference is in the implementation of ipop *)
	    let popRc vi =
	      (* use zero for size if vi isn't an array as that produces better
		 code when inlining the rc_adjust function (a 0 size argument
		 to rc_adjust means "assume it's not an array") *)
	      let viSize = 
		if isArrayType vi.vtype then
		  SizeOfE (v2e vi)
		else
		  zero
	      in
	      [ rcAdjustSize fi !currentFn (Var vi, NoOffset) (-1) viSize loc; 
		iPushPopCall rcFunctions.ipop fi !currentFn vi loc ] in
	    let popInstr = Instr (L.concat (L.map popRc (nonTemps vars))) in
	    let popStmt = mkStmt popInstr in
	    let popBlock = mkBlock [ popStmt; mkStmt s.skind ] in
	    s.skind <- Block popBlock;
	    SkipChildren
        | _ -> DoChildren
      end
  end

exception NoType

let rcSizeOfType (e:exp) : typ =
      match e with 
      | SizeOf t -> t           (* type *)
      | SizeOfE e -> typeOf e   (* expression *)
      | _ -> raise NoType            
             
(* Rewrite calls to hs_typeof(X) to the appropriate "rc_adjust..."
   function, or to null.
   hs_typeof is a macro that expands to 
     'sizeof(X) + __hs_magic_typeof' 
   and can thus be used to get both the type of types and expressions. *)
class rcTypeOf (fi:file) : cilVisitor =
  object (self)
    inherit nopCilVisitor as super

    val currentGlob : varinfo ref = ref dummyFunDec.svar;
    method vglob (g:global) = match g with
      | GVar (v, _, _) | GFun ({svar = v}, _) ->
        currentGlob := v;
        DoChildren
      | _ -> DoChildren

    method vexpr (e:exp) =  
      match e with
      | BinOp(PlusA, typeinfo, Lval(Var vi, NoOffset), _) 
        when vi.vname = "__hs_magic_typeof" ->
          begin
            try
              let t = rcSizeOfType typeinfo in 
              let vi = rcAdjustForType fi !currentGlob t !currentLoc in
              ChangeTo (v2e vi)
            with 
            | NoRcPointers -> ChangeTo zero
            | NoType ->
                ignore (errorLoc !currentLoc "Invalid use of __hs_magic_typeof");
                DoChildren  
          end
      | Lval (Var vi,_)  when vi.vname = "__hs_magic_typeof" ->
          ignore(errorLoc !currentLoc "Invalid use of __hs_magic_typeof");
          DoChildren
      | _ -> DoChildren
  end

class stripRcTypeOf : cilVisitor =
  object (self)
    inherit nopCilVisitor as super
    
    method vexpr (e:exp) = 
      match e with 
      | BinOp(PlusA,typeinfo,Lval(Var vi,NoOffset),_)
                        when vi.vname = "__hs_magic_typeof" ->
            ChangeTo (Const(CInt64(Int64.zero,IUInt,None)))
      | Lval (Var vi,_) when vi.vname = "__hs_magic_typeof" ->
            ignore(errorLoc !currentLoc "Invalid use of __hs_magic_typeof");
            DoChildren  
      | _ -> DoChildren        
    
  end


(* is this instruction a call to the given function *)
let isCallTo (f:varinfo) (i:instr) : bool = match i with
   | Call(None, Lval(Var vi, NoOffset), _, _) when vi == f -> true
   | _ -> false

(* rewrite calls to __builtin_clear to the appropriate sequence
   of clearing operations *)
(* TODO: share code with rcTypeOf, which is very similar *)
class rcClear : cilVisitor =
  object (self)
    inherit nopCilVisitor as super
    val currentFn : fundec ref = ref dummyFunDec;
    method vfunc (f: fundec) = 
      currentFn := f;
      DoChildren
          
    method private clearStmts (i:instr) = 
      match i with 
      | Call(None, called, [target], loc) 
                when isCallTo rcFunctions.rcclear i ->
          let lval = (Mem target,NoOffset) in
          clearByType !currentFn (typeOfLval lval) lval loc
      | Call(_,_,_,loc) when isCallTo rcFunctions.rcclear i ->
          ignore(errorLoc loc "Invalid use of __builtin_clear"); []
      | _ -> [i2s i]
 
    method vstmt (s:stmt) = 
      match s.skind with
      | Instr insts when List.exists (isCallTo rcFunctions.rcclear) insts ->
        let stmts = List.concat (List.map self#clearStmts insts) in
	let news = Block (mkBlock (compactStmts stmts)) in
	s.skind <- news;
	SkipChildren
      | _ -> DoChildren
  end   


let refsCountedData exp = match typeOf exp with
    | TPtr (t,_) -> typeContainsCountedPointers t
    | _ -> false

(* check for use of functions like memcpy and memset *)
class rcCheckBadFunc : cilVisitor = 
  object (self) 
    inherit nopCilVisitor as super
    
    method vinst (i:instr) = match i with
      | Call(_, called, args, loc) 
            when isBadfun (typeOf called) 
            && List.exists refsCountedData args ->
                ignore(warnLoc loc 
                        "Uncounted overwriting of counted pointers");
                DoChildren
      | _ -> DoChildren                      
  end

(* add tracing calls *)
class rcTrace (fi:file) : cilVisitor =
  object (self)
    inherit nopCilVisitor as super

    method vinst (i:instr) = match i with
      | Call(res, called, _, loc) when isRctrace (typeOf called) ->
	  ChangeTo [Call (None, v2e rcFunctions.rctrace, [], loc); i]
      | _ -> DoChildren
  end


(* convert any hs_typeof commands into NULLs *)
let norcProcessFile (fi:file) : unit =
  let doRcClear = new rcClear in
  let rcProcess (f:fundec) (loc:location) : unit =
    (* transform __builtin_clear to the appropriate clearing statements *)
    ignore (visitCilFunction doRcClear f)
  in
  iterGlobals fi (onlyFunctions (skipAdjustFunctions rcProcess));
  ignore (visitCilFile (new stripRcTypeOf) fi)
        

(* Add reference counting code to 'fi' *)
let rcProcessFile (fi:file) : unit =
  let doRcTypeOf = new rcTypeOf fi in
  let rcProcess (f:fundec) (loc:location) : unit =
    (* Decide which local variables to handle with rcpush/rcpop (oVars), 
       and which to handle like regular heap locations (uVars) *)
    let interesting vi = typeContainsCountedPointers vi.vtype in
    let optimisable vi = (not vi.vaddrof) && (isPointer vi.vtype) && (not (!Ivyoptions.noDefer)) in
    let optimised vi = (interesting vi) && (optimisable vi)
    and unoptimised vi = (interesting vi) && (not (optimisable vi)) in

    let allLocals = f.sformals @ f.slocals in
    
    let oVars, uVars = 
        L.filter optimised allLocals, L.filter unoptimised allLocals in

    let doAssigns = new rcAssignments fi oVars 
    and doExit = new rcOnExit fi uVars
    and doRcTrace = new rcTrace fi 
    and doRcClear = new rcClear in

    (* refcount heap writes *)
    ignore (visitCilFunction doAssigns f); 

    (* refcount formals in uVars on function entry *)
    rcOnEntry fi f (L.filter unoptimised f.sformals) loc;

    (* push address of locals in uVars to parallel stack on function entry, 
       for longjmp *) 
    pushOnEntry fi f uVars loc;

    (* pop address of local in uVars from parallel stack on function exit
       (for longjmp), and deref them *)
    if uVars != [] then 
      ignore (visitCilFunction doExit f);

    (* transform __builtin_clear to the appropriate clearing statements *)
    ignore (visitCilFunction doRcClear f);
    
    ignore (visitCilFunction (new rcCheckBadFunc) f); 

    (* add tracing calls *)
    ignore (visitCilFunction doRcTrace f);
    
    (* call rcpush/rcpop for locals in oVars *)
    if (not !Ivyoptions.noLocals) then
      rcLocals f oVars
  in

  let rcProcessGlobal (g:global) : unit =
    (* transform hs_typeof to the appropriate value *)
    ignore (visitCilGlobal doRcTypeOf g)
    
  in
  iterGlobals fi (onlyFunctions (skipAdjustFunctions rcProcess));
  iterGlobals fi rcProcessGlobal


let postProcessFile (f : file) =
  (* Add #include directive for opsFile *)
  f.globals <- (GText ("#include <" ^ !Ivyoptions.opsFile ^ ">\n\n"))::f.globals;
  ()
