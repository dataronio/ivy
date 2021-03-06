March 20, 2007

Parallel BZIP2 v1.0.1 - by: Jeff Gilchrist <pbzip2@compression.ca>
Available at:  http://compression.ca/

This is the README for pbzip2, a parallel implementation of the
bzip2 block-sorting file compressor, version 1.0.  The output of
this version should be fully compatible with bzip2 v1.0.2 or newer
(ie: anything compressed with pbzip2 can be decompressed with bzip2).

pbzip2 is distributed under a BSD-style license.  For details,
see the file COPYING.


1. HOW TO BUILD -- UNIX

Type `make'.  This builds the pbzip2 program and dynamically
links to the libbzip2 library.

If you do not have libbzip2 installed on your system, you should
first go to http://www.bzip.org/ and install it.

Debian users need the package "libbz2-dev".  If you want to
install a pre-built package on Debian, run the following command:
'apt-get update; apt-get install pbzip2'

If you would like to build pbzip2 with a statically linked
libbzip2 library, download the bzip2 source from the above site,
compile it, and copy the libbz2.a and bzlib.h files into the
pbzip2 source directory.  Then type `make pbzip2-static'.

Note: This software has been tested on Linux (Intel, Alpha), 
Solaris (Sparc), HP-UX, Irix (SGI), and Tru64/OSF1 (Alpha).


2. HOW TO BUILD -- Windows

On Windows, pbzip2 can be compiled using Cygwin or MinGW.

If you do not have libbzip2 installed on your system, you should
first go to http://www.bzip.org/ and install it.

Cygwin can be found at:  http://www.cygwin.com/
From a Cygwin shell, go to the directory where the pbzip2 source
files are located and type `make'.  This builds the pbzip2
program and dynamically links to the libbzip2 library.

MinGW can be found at:  http://www.mingw.org/
You will also need http://sources.redhat.com/pthreads-win32/
to compile in MinGW.  You can take a precompiled binary 
libpthreadGC2.a and associated pthreadGC2.dll file from the 
dll-latest/lib repository.  Copy libpthreadGC2.a to 
/lib/libpthread.a of your MinGW install and then copy the 
pthreadGC2.dll to the pbzip2 directory or to a directory
in your Windows path (ie: WINDOWS\SYSTEM32).
From a MinGW shell, go to the directory where the pbzip2 source
files are located and type `make'.  This builds the pbzip2
program and links the libbzip2 and libpthread library.

If you would like to build pbzip2 with a statically linked
libbzip2 library, download the bzip2 source from the above site,
compile it, and copy the libbz2.a file into the pbzip2 source
directory.  Then type `make pbzip2-static'.


3. DISCLAIMER

   I TAKE NO RESPONSIBILITY FOR ANY LOSS OF DATA ARISING FROM THE
   USE OF THIS PROGRAM, HOWSOEVER CAUSED.

   DO NOT COMPRESS ANY DATA WITH THIS PROGRAM UNLESS YOU ARE
   PREPARED TO ACCEPT THE POSSIBILITY, HOWEVER SMALL, THAT THE
   DATA WILL NOT BE RECOVERABLE.

* Portions of this README were copied directly from the bzip2 README
  written by Julian Seward.

  
4. PBZIP2 DATA FORMAT

You should be able to compress files larger than 4GB with pbzip2.

Files that are compressed with pbzip2 are broken up into pieces and
each individual piece is compressed.  This is how pbzip2 runs faster
on multiple CPUs since the pieces can be compressed simultaneously.
The final .bz2 file may be slightly larger than if it was compressed
with the regular bzip2 program due to this file splitting (usually
less than 0.2% larger).  Files that are compressed with pbzip2 will
also gain considerable speedup when decompressed using pbzip2.

Files that were compressed using bzip2 will not see speedup since
bzip2 pacakages the data into a single chunk that cannot be split
between processors.  If you have a large file that was created with
bzip2 (say 1.5GB for example) you will likely not be able to
decompress the file with pbzip2 since pbzip2 will try to allocate
1.5GB of memory to decompress it, and that call might fail depending
on your system resources.  If the same 1.5GB file had of been
compressed with pbzip2, it would decompress fine with pbzip2.  If
you are unable to decompress a file with pbzip2 due to its size, use
the regular bzip2 instead.

A file compressed with bzip2 will be one compressed stream of data
that looks like this:
[-----------------------------------------------------]

Data compressed with pbzip2 is broken into multiple streams and each
stream is bzip2 compressed looking like this:
[-----|-----|-----|-----|-----|-----|-----|-----|-----]

If you are writing software with libbzip2 to decompress data created
with pbzip2, you must take into account that the data contains multiple
bzip2 streams so you will encounter end-of-stream markers from libbzip2
after each stream and must look-ahead to see if there are any more
streams to process before quitting.  The bzip2 program itself will
automatically handle this condition.


5. USAGE

The pbzip2 program is a parallel version of bzip2 for use on shared
memory machines.  It provides near-linear speedup when used on true
multi-processor machines and 5-10% speedup on Hyperthreaded machines.
The output is fully compatible with the regular bzip2 data so any
files created with pbzip2 can be uncompressed by bzip2 and vice-versa.
The default settings for pbzip2 will work well in most cases.  The
only switch you will likely need to use is -d to decompress files and 
-p to set the # of processors for pbzip2 to use if autodetect is not
supported on your system, or you want to use a specific # of CPUs.

Usage:  pbzip2 [-1 .. -9] [-b#cdfklp#rtvV] <filename> <filename2> <filenameN>

Switches:
  -b#      : where # is the file block size in 100k (default 9 = 900k)
  -c       : output to standard out (stdout)
  -d       : decompress file
  -f       : force, overwrite existing output file
  -k       : keep input file, don't delete
  -l       : load average determines max number processors to use
  -p#      : where # is the number of processors (default: autodetect or 2)
  -r       : read entire input file into RAM and split between processors
  -t       : test compressed file integrity
  -v       : verbose mode
  -V       : display version info for pbzip2 then exit
  -1 .. -9 : set BWT block size to 100k .. 900k (default 900k)
  

Example:  pbzip2 myfile.tar

This example will compress the file "myfile.tar" into the compressed
file "myfile.tar.bz2".  It will use the autodetected # of processors
(or 2 processors if autodetect not supported) with the default file
block size of 900k and default BWT block size of 900k.


Example:  pbzip2 -b15vk myfile.tar

This example will compress the file "myfile.tar" into the compressed
file "myfile.tar.bz2".  It will use the autodetected # of processors
(or 2 processors if autodetect not supported) with a file block
size of 1500k and a BWT block size of 900k.  Verbose mode will be
enabled so progress and other messages will be output to the display
and the file myfile.tar will not be deleted after compression is 
finished.


Example:  pbzip2 -p4 -r -5 myfile.tar second*.txt

This example will compress the file "myfile.tar" into the compressed
file "myfile.tar.bz2".  It will use 4 processors with a BWT block
size of 500k.  The file block size will be the size of "myfile.tar"
divided by 4 (# of processors) so that the data will be split
evenly among each processor.  This requires you have enough RAM for
pbzip2 to read the entire file into memory for compression.  pbzip2
will then use the same options to compress all other files that
match the wildcard "second*.txt" in that directory.


Example:  pbzip2 -l myfile.tar

This example will compress the file "myfile.tar" into the compressed
file "myfile.tar.bz2".  It will use the autodetected # of processors
(or 2 processors if autodetect not supported) if the 1 minute load
average is less than 0.5, otherwise it will select the maximum # of
processors so that only idle processors are used for pbzip2.  If the
system has 4 processors and the load average is 2.00, then pbzip2
will use 2 processors to compress the data. 


Example:  pbzip2 -d myfile.tar.bz2

This example will decompress the file "myfile.tar.bz2" into the
decompressed file "myfile.tar".  It will use the autodetected # of
processors (or 2 processors if autodetect not supported).
The switches -b, -r, -t, and -1..-9 are not valid for decompression.
