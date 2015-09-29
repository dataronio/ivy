#ifndef OCT_CONFIG_H__
#define OCT_CONFIG_H__

#ifdef __cplusplus
extern "C" {
#endif

/* oct_config.h.  Generated by configure.  */
/* Define if you have the ANSI C header files.  */
#define STDC_HEADERS 1

/* Define if your processor stores words with the most significant
   byte first (like Motorola and SPARC, unlike Intel and VAX).  */
/* #undef WORDS_BIGENDIAN */

/* Define if you have the <dlfcn.h> header file.  */
#define HAVE_DLFCN_H 1

/* Define if you have the m library (-lm).  */
#define HAVE_LIBM 1

typedef unsigned int var_t;
static const var_t max_index = 1<<(sizeof(int)*8-2);

#ifndef __cplusplus
#undef OCT_HAS_BOOL
#else
#define OCT_HAS_BOOL
#endif

#ifdef __cplusplus
}
#endif

#endif /* OCT_CONFIG_H__ */
