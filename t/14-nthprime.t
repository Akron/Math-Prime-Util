#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Math::Prime::Util qw/nth_prime nth_prime_lower nth_prime_upper nth_prime_approx/;

my $use64 = Math::Prime::Util::_maxbits > 32;
my $extra = defined $ENV{RELEASE_TESTING} && $ENV{RELEASE_TESTING};

plan tests => 7*2 + 9*3 + ($extra ? 9 : 7) + ($use64 ? 4*3 : 0);

my %pivals32 = (
                  1 => 0,
                 10 => 4,
                100 => 25,
               1000 => 168,
              10000 => 1229,
             100000 => 9592,
            1000000 => 78498,
);

while (my($n, $pin) = each (%pivals32)) {
  my $next = $pin+1;
  cmp_ok( nth_prime($pin), '<=', $n, "nth_prime($pin) <= $n");
  cmp_ok( nth_prime($next), '>=', $n, "nth_prime($next) >= $n");
}

my %nthprimes32 = (
                  1 => 2,
                 10 => 29,
                100 => 541,
               1000 => 7919,
              10000 => 104729,
             100000 => 1299709,
            1000000 => 15485863,
           10000000 => 179424673,
          100000000 => 2038074743,
);
my %nthprimes64 = (
         1000000000 => 22801763489,
        10000000000 => 252097800623,
       100000000000 => 2760727302517,
      1000000000000 => 29996224275833,
     # TODO: find more
);

while (my($n, $nth) = each (%nthprimes32)) {
  cmp_ok( nth_prime_upper($n), '>=', $nth, "nth_prime($n) <= upper estimate" );
  cmp_ok( nth_prime_lower($n), '<=', $nth, "nth_prime($n) >= lower estimate" );

  if ( ($n <= 2000000) || $extra ) {
    is( nth_prime($n), $nth, "nth_prime($n) = $nth" );
  }

  my $approx = nth_prime_approx($n);
  my $percent_limit = ($n >= 775) ? 1 : 2;
  cmp_ok( abs($nth - $approx) / $nth, '<=', $percent_limit/100.0, "nth_prime_approx($n) = $approx within $percent_limit\% of $nth");
}

if ($use64) {
  while (my($n, $nth) = each (%nthprimes64)) {
    cmp_ok( nth_prime_upper($n), '>=', $nth, "nth_prime($n) <= upper estimate" );
    cmp_ok( nth_prime_lower($n), '<=', $nth, "nth_prime($n) >= lower estimate" );

    my $approx = nth_prime_approx($n);
    my $percent_limit = 0.001;
    cmp_ok( abs($nth - $approx) / $nth, '<=', $percent_limit/100.0, "nth_prime_approx($n) = $approx within $percent_limit\% of $nth");
  }
}
