#ifndef MPU_UTIL_H
#define MPU_UTIL_H

#include "ptypes.h"

extern int _XS_is_prime(UV x);
extern int is_definitely_prime(UV x);
extern UV  next_trial_prime(UV x);
extern UV  _XS_next_prime(UV x);
extern UV  _XS_prev_prime(UV x);

extern UV  _XS_prime_count(UV low, UV high);
extern UV  _XS_nth_prime(UV x);

extern double _XS_ExponentialIntegral(double x);
extern double _XS_LogarithmicIntegral(double x);
extern double _XS_RiemannR(double x);

/* Above this value, is_prime will do deterministic Miller-Rabin */
/* With 64-bit math, we can do much faster mulmods from 2^16-2^32 */
#if (BITS_PER_WORD == 64) || HAVE_STD_U64
  #define MPU_PROB_PRIME_BEST  UVCONST(100000)
#else
  #define MPU_PROB_PRIME_BEST  UVCONST(100000000)
#endif

#endif
