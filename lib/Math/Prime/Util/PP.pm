package Math::Prime::Util::PP;
use strict;
use warnings;
use Carp qw/carp croak confess/;

BEGIN {
  $Math::Prime::Util::PP::AUTHORITY = 'cpan:DANAJ';
  $Math::Prime::Util::PP::VERSION = '0.20';
}

# The Pure Perl versions of all the Math::Prime::Util routines.
#
# Some of these will be relatively similar in performance, some will be
# very slow in comparison.
#
# Most of these are pretty simple.  Also, you really should look at the C
# code for more detailed comments, including references to papers.

my $_uv_size;
BEGIN {
  use Config;
  $_uv_size =
   (   (defined $Config{'use64bitint'} && $Config{'use64bitint'} eq 'define')
    || (defined $Config{'use64bitall'} && $Config{'use64bitall'} eq 'define')
    || (defined $Config{'longsize'} && $Config{'longsize'} >= 8)
   )
   ? 64
   : 32;
  no Config;
}
sub _PP_prime_maxbits { $_uv_size }

# If $n < $_half_word, then $n*$n will be exact.
my $_half_word = (~0 == 18446744073709551615) ? 4294967296 :    # 64-bit
                 (~0 ==           4294967295) ?      65536 :    # 32-bit
                 (~0 ==                   -1) ?   1000**10 :    # bignum
                                                         0 ;    # No idea
# With Perl 5.6.2, (114438327*114438327) % 122164969  !=  75730585
$_half_word >>= 7 if $_uv_size == 64 && $] < 5.008;

# Infinity in Perl is rather O/S specific.
our $_Infinity = 0+'inf';
$_Infinity = 20**20**20 if 65535 > $_Infinity;   # E.g. Windows
our $_Neg_Infinity = -$_Infinity;

my $_have_MPFR = -1;

my $_precalc_size = 0;
sub prime_precalc {
  my($n) = @_;
  croak "Input must be a positive integer" unless _is_positive_int($n);
  $_precalc_size = $n if $n > $_precalc_size;
}
sub prime_memfree {
  $_precalc_size = 0;
}
sub _get_prime_cache_size { $_precalc_size }
sub _prime_memfreeall { prime_memfree; }


sub _is_positive_int {
  ((defined $_[0]) && ($_[0] !~ tr/0123456789//c));
}

sub _validate_positive_integer {
  my($n, $min, $max) = @_;
  croak "Parameter must be defined" if !defined $n;
  croak "Parameter '$n' must be a positive integer"
        if ref($n) ne 'Math::BigInt' && $n =~ tr/0123456789//c;
  croak "Parameter '$n' must be >= $min" if defined $min && $n < $min;
  croak "Parameter '$n' must be <= $max" if defined $max && $n > $max;
  if ($n <= ~0) {
    $_[0] = $_[0]->as_number() if ref($_[0]) eq 'Math::BigFloat';
    $_[0] = int($_[0]->bstr) if ref($_[0]) eq 'Math::BigInt';
  } elsif (ref($n) ne 'Math::BigInt') {
    croak "Parameter '$n' outside of integer range" if !defined $bigint::VERSION;
    $_[0] = Math::BigInt->new("$n"); # Make $n a proper bigint object
    $_[0]->upgrade(undef) if $_[0]->upgrade();  # Stop BigFloat upgrade
  } else {
    $_[0]->upgrade(undef) if $_[0]->upgrade();  # Stop BigFloat upgrade
  }
  # One of these will be true:
  #     1) $n <= max and $n is not a bigint
  #     2) $n  > max and $n is a bigint
  1;
}


my @_primes_small = (
   0,2,3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,97,
   101,103,107,109,113,127,131,137,139,149,151,157,163,167,173,179,181,191,
   193,197,199,211,223,227,229,233,239,241,251,257,263,269,271,277,281,283,
   293,307,311,313,317,331,337,347,349,353,359,367,373,379,383,389,397,401,
   409,419,421,431,433,439,443,449,457,461,463,467,479,487,491,499);
my @_prime_count_small = (
   0,0,1,2,2,3,3,4,4,4,4,5,5,6,6,6,6,7,7,8,8,8,8,9,9,9,9,9,9,10,10,
   11,11,11,11,11,11,12,12,12,12,13,13,14,14,14,14,15,15,15,15,15,15,
   16,16,16,16,16,16,17,17,18,18,18,18,18,18,19);
my @_prime_next_small = (
   2,2,3,5,5,7,7,11,11,11,11,13,13,17,17,17,17,19,19,23,23,23,23,
   29,29,29,29,29,29,31,31,37,37,37,37,37,37,41,41,41,41,43,43,47,
   47,47,47,53,53,53,53,53,53,59,59,59,59,59,59,61,61,67,67,67,67,67,67,71);

# For wheel-30
my @_prime_indices = (1, 7, 11, 13, 17, 19, 23, 29);
my @_nextwheel30 = (1,7,7,7,7,7,7,11,11,11,11,13,13,17,17,17,17,19,19,23,23,23,23,29,29,29,29,29,29,1);
my @_prevwheel30 = (29,29,1,1,1,1,1,1,7,7,7,7,11,11,13,13,13,13,17,17,19,19,19,19,23,23,23,23,23,23);

sub _is_prime7 {  # n must not be divisible by 2, 3, or 5
  my($n) = @_;

  if ($n < 61*61) {
    foreach my $i (qw/7 11 13 17 19 23 29 31 37 41 43 47 53 59/) {
      return 2 if $i*$i > $n;
      return 0 if !($n % $i);
    }
    return 2;
  }

  return 0 if !($n %  7) || !($n % 11) || !($n % 13) || !($n % 17) ||
              !($n % 19) || !($n % 23) || !($n % 29) || !($n % 31) ||
              !($n % 37) || !($n % 41) || !($n % 43) || !($n % 47) ||
              !($n % 53) || !($n % 59);

  return Math::Prime::Util::is_prob_prime($n) if $n > 10_000_000;

  my $limit = int(sqrt($n));
  my $i = 61;
  while (($i+30) <= $limit) {
    return 0 if !($n % $i);  $i += 6;
    return 0 if !($n % $i);  $i += 4;
    return 0 if !($n % $i);  $i += 2;
    return 0 if !($n % $i);  $i += 4;
    return 0 if !($n % $i);  $i += 2;
    return 0 if !($n % $i);  $i += 4;
    return 0 if !($n % $i);  $i += 6;
    return 0 if !($n % $i);  $i += 2;
  }
  while (1) {
    last if $i > $limit;  return 0 if !($n % $i);  $i += 6;
    last if $i > $limit;  return 0 if !($n % $i);  $i += 4;
    last if $i > $limit;  return 0 if !($n % $i);  $i += 2;
    last if $i > $limit;  return 0 if !($n % $i);  $i += 4;
    last if $i > $limit;  return 0 if !($n % $i);  $i += 2;
    last if $i > $limit;  return 0 if !($n % $i);  $i += 4;
    last if $i > $limit;  return 0 if !($n % $i);  $i += 6;
    last if $i > $limit;  return 0 if !($n % $i);  $i += 2;
  }
  2;
}

sub is_prime {
  my($n) = @_;
  _validate_positive_integer($n);

  return 2 if ($n == 2) || ($n == 3) || ($n == 5);  # 2, 3, 5 are prime
  return 0 if $n < 7;             # everything else below 7 is composite
                                  # multiples of 2,3,5 are composite
  return 0 if !($n % 2) || !($n % 3) || !($n % 5);
  return _is_prime7($n);
}

# Possible sieve storage:
#   1) vec with mod-30 wheel:   8 bits  / 30
#   2) vec with mod-2 wheel :  15 bits  / 30
#   3) str with mod-30 wheel:   8 bytes / 30
#   4) str with mod-2 wheel :  15 bytes / 30
#
# It looks like using vecs is about 2x slower than strs, and the strings also
# let us do some fast operations on the results.  E.g.
#   Count all primes:
#      $count += $$sieveref =~ tr/0//;
#   Loop over primes:
#      foreach my $s (split("0", $$sieveref, -1)) {
#        $n += 2 + 2 * length($s);
#        .. do something with the prime $n
#      }
#
# We're using method 4, though sadly it is memory intensive relative to the
# other methods.  I will point out that it is 30-60x less memory than sieves
# using an array, and the performance of this function is over 10x that
# of naive sieves like found on RosettaCode.

sub _sieve_erat_string {
  my($end) = @_;
  $end-- if ($end & 1) == 0;
  my $s_end = $end >> 1;

  my $whole = int( $s_end / 15);   # Prefill with 3 and 5 already marked.
  croak "Sieve too large" if $whole > 1_145_324_612;  # ~32 GB string
  my $sieve = "100010010010110" . "011010010010110" x $whole;
  substr($sieve, $s_end+1) = '';   # Ensure we don't make too many entries
  my ($n, $limit) = ( 7, int(sqrt($end)) );
  while ( $n <= $limit ) {
    for (my $s = ($n*$n) >> 1; $s <= $s_end; $s += $n) {
      substr($sieve, $s, 1) = '1';
    }
    do { $n += 2 } while substr($sieve, $n>>1, 1);
  }
  \$sieve;
}

# TODO: this should be plugged into precalc, memfree, etc. just like the C code
{
  my $primary_size_limit = 15000;
  my $primary_sieve_size = 0;
  my $primary_sieve_ref;
  sub _sieve_erat {
    my($end) = @_;

    return _sieve_erat_string($end) if $end > $primary_size_limit;

    if ($primary_sieve_size == 0) {
      $primary_sieve_size = $primary_size_limit;
      $primary_sieve_ref = _sieve_erat_string($primary_sieve_size);
    }
    my $sieve = substr($$primary_sieve_ref, 0, ($end+1)>>1);
    \$sieve;
  }
}


sub _sieve_segment {
  my($beg,$end) = @_;
  croak "Internal error: segment beg is even" if ($beg % 2) == 0;
  croak "Internal error: segment end is even" if ($end % 2) == 0;
  croak "Internal error: segment end < beg" if $end < $beg;
  croak "Internal error: segment beg should be >= 3" if $beg < 3;
  my $range = int( ($end - $beg) / 2 ) + 1;

  # Prefill with 3 and 5 already marked, and offset to the segment start.
  my $whole = int( ($range+14) / 15);
  my $startp = ($beg % 30) >> 1;
  my $sieve = substr("011010010010110", $startp) . "011010010010110" x $whole;
  # Set 3 and 5 to prime if we're sieving them.
  substr($sieve,0,2) = "00" if $beg == 3;
  substr($sieve,0,1) = "0"  if $beg == 5;
  # Get rid of any extra we added.
  substr($sieve, $range) = '';

  # If the end value is below 7^2, then the pre-sieve is all we needed.
  return \$sieve if $end < 49;

  my $limit = int(sqrt($end)) + 1;
  # For large value of end, it's a huge win to just walk primes.
  my $primesieveref = _sieve_erat($limit);
  my $p = 7-2;
  foreach my $s (split("0", substr($$primesieveref, 3), -1)) {
    $p += 2 + 2 * length($s);
    my $p2 = $p*$p;
    last if $p2 > $end;
    if ($p2 < $beg) {
      $p2 = int($beg / $p) * $p;
      $p2 += $p if $p2 < $beg;
      $p2 += $p if ($p2 % 2) == 0;   # Make sure p2 is odd
    }
    # With large bases and small segments, it's common to find we don't hit
    # the segment at all.  Skip all the setup if we find this now.
    if ($p2 <= $end) {
      # Inner loop marking multiples of p
      # (everything is divided by 2 to keep inner loop simpler)
      my $filter_end = ($end - $beg) >> 1;
      my $filter_p2  = ($p2  - $beg) >> 1;
      while ($filter_p2 <= $filter_end) {
        substr($sieve, $filter_p2, 1) = "1";
        $filter_p2 += $p;
      }
    }
  }
  \$sieve;
}

sub trial_primes {
  my($low,$high) = @_;
  if (!defined $high) {
    $high = $low;
    $low = 2;
  }
  _validate_positive_integer($low);
  _validate_positive_integer($high);

  return if $low > $high;

  my @primes;
  $low-- if $low >= 2;
  my $curprime = next_prime($low);
  while ($curprime <= $high) {
    push @primes, $curprime;
    $curprime = next_prime($curprime);
  }
  return \@primes;
}

sub primes {
  my $optref = (ref $_[0] eq 'HASH')  ?  shift  :  {};
  croak "no parameters to primes" unless scalar @_ > 0;
  croak "too many parameters to primes" unless scalar @_ <= 2;
  my $low = (@_ == 2)  ?  shift  :  2;
  my $high = shift;
  my $sref = [];

  _validate_positive_integer($low);
  _validate_positive_integer($high);

  return $sref if ($low > $high) || ($high < 2);

  # Ignore method options in this code

  # At some point even the pretty-fast pure perl sieve is going to be a
  # dog, and we should move to trials.  This is typical with a small range
  # on a large base.  More thought on the switchover should be done.
  return trial_primes($low, $high) if ref($low)  eq 'Math::BigInt'
                                   || ref($high) eq 'Math::BigInt'
                                   || ($low > 1_000_000_000_000 && ($high-$low) < int($low/1_000_000));

  push @$sref, 2  if ($low <= 2) && ($high >= 2);
  push @$sref, 3  if ($low <= 3) && ($high >= 3);
  push @$sref, 5  if ($low <= 5) && ($high >= 5);
  $low = 7 if $low < 7;
  $low++ if ($low % 2) == 0;
  $high-- if ($high % 2) == 0;
  return $sref if $low > $high;

  if ($low == 7) {
    my $sieveref = _sieve_erat($high);
    my $n = $low - 2;
    foreach my $s (split("0", substr($$sieveref, 3), -1)) {
      $n += 2 + 2 * length($s);
      push @$sref, $n if $n <= $high;
    }
  } else {
    my $sieveref = _sieve_segment($low,$high);
    my $n = $low - 2;
    foreach my $s (split("0", $$sieveref, -1)) {
      $n += 2 + 2 * length($s);
      push @$sref, $n if $n <= $high;
    }
  }
  $sref;
}

sub next_prime {
  my($n) = @_;
  _validate_positive_integer($n);
  if ($n >= ((_PP_prime_maxbits == 32) ? 4294967291 : 18446744073709551557)) {
    return 0 if ref($_[0]) ne 'Math::BigInt';
    $n = $_[0];  # $n is a bigint now
  }
  return $_prime_next_small[$n] if $n <= $#_prime_next_small;

  # Be careful trying to do:
  #     my $d = int($n/30);
  #     my $m = $n - $d*30;
  # See:  int(9999999999999999403 / 30) => 333333333333333312  (off by 1)
  my $m = $n % 30;
  my $d = ($n - $m) / 30;
  if ($m == 29) { $d++;  $m = 1;} else { $m = $_nextwheel30[$m]; }
  while (!_is_prime7($d*30+$m)) {
    $m = $_nextwheel30[$m];
    $d++ if $m == 1;
  }
  $d*30 + $m;
}

sub prev_prime {
  my($n) = @_;
  _validate_positive_integer($n);
  if ($n <= 7) {
    return ($n <= 2) ? 0 : ($n <= 3) ? 2 : ($n <= 5) ? 3 : 5;
  }

  $n++ if ($n % 2) == 0;
  do {
    $n -= 2;
  } while ( (($n % 3) == 0) || (($n % 5) == 0) || (!_is_prime7($n)) );
  $n;

  # This is faster for larger intervals, slower for short ones.
  #my $base = 30 * int($n/30);
  #my $in = 0;  $in++ while ($n - $base) > $_prime_indices[$in];
  #if (--$in < 0) {  $base -= 30; $in = 7;  }
  #$n = $base + $_prime_indices[$in];
  #while (!_is_prime7($n)) {
  #  if (--$in < 0) {  $base -= 30; $in = 7;  }
  #  $n = $base + $_prime_indices[$in];
  #}
  #$n;

  #my $m = $n % 30;
  #my $d = int( ($n - $m) / 30 );
  #do {
  #  $m = $_prevwheel30[$m];
  #  $d-- if $m == 29;
  #} while (!_is_prime7($d*30+$m));
  #$d*30+$m;
}

#############################################################################
#                       Lehmer prime count
#
sub _mapes {
  my($v, $ma) = @_;
  return $v if $ma == 0;
  my $val = $v-int($v/2);
  $val += -int($v/3)+int($v/6) if $ma >= 2;
  $val += -int($v/5)+int($v/10)+int($v/15)-int($v/30) if $ma >= 3;
  $val += -int($v/7)+int($v/14)+int($v/21)-int($v/42)+int($v/35)-int($v/70)-int($v/105)+int($v/210) if $ma >= 4;
  $val += -int($v/11)+int($v/22)+int($v/33)-int($v/66)+int($v/55)-int($v/110)-int($v/165)+int($v/330)+int($v/77)-int($v/154)-int($v/231)+int($v/462)-int($v/385)+int($v/770)+int($v/1155)-int($v/2310) if $ma >= 5;
  $val += -int($v/13)+int($v/26)+int($v/39)-int($v/78)+int($v/65)-int($v/130)-int($v/195)+int($v/390)+int($v/91)-int($v/182)-int($v/273)+int($v/546)-int($v/455)+int($v/910)+int($v/1365)-int($v/2730)+int($v/143)-int($v/286)-int($v/429)+int($v/858)-int($v/715)+int($v/1430)+int($v/2145)-int($v/4290)-int($v/1001)+int($v/2002)+int($v/3003)-int($v/6006)+int($v/5005)-int($v/10010)-int($v/15015)+int($v/30030) if $ma >= 6;
  return $val;
}

sub _legendre_phi {
  my ($x, $a, $primes) = @_;
  return _mapes($x,$a) if $a <= 6;
  return ($x > 0 ? 1 : 0) if $x < $primes->[$a];

  my $sum = 0;
  my %vals = ( $x => 1 );
  while ($a > 6) {
    my $primea = $primes->[$a-1];
    my %newvals;
    while (my($v,$c) = each %vals) {
      next if $c == 0;
      # next if $v < $primea;
      $newvals{$v} += $c;
      my $sval = int($v / $primea);
      if ($sval >= $primea) {
        $newvals{$sval} -= $c;
      } else {
        $sum -= $c;
      }
    }
    %vals = %newvals;
    $a--;
  }
  while (my($v,$c) = each %vals) {
    next if $c == 0;
    $sum += $c * _mapes($v, $a);
  }
  return $sum;
}

sub _sieve_prime_count {
  my $high = shift;
  return (0,0,1,2,2,3,3)[$high] if $high < 7;
  $high-- if ($high % 2) == 0; # Make high go to odd number.

  my $sieveref = _sieve_erat($high);
  my $count = 1 + $$sieveref =~ tr/0//;
  return $count;
}

sub _count_with_sieve {
  my ($sref, $high) = @_;
  return (0,0,1,2,2,3,3)[$high] if $high < 7;
  $high-- if ($high % 2) == 0; # Make high go to odd number.
  my $send = ($high >> 1) + 1;

  if ( !defined $sref || $send > length($$sref) ) {
    # We could take the full count of $sref, then segment sieve to high.
    $sref = _sieve_erat($high);
    return 1 + $$sref =~ tr/0//;
  }
  return 1 + substr($$sref, 0, $send) =~ tr/0//;
}

sub _lehmer_pi {
  my $x = shift;
  return _sieve_prime_count($x) if $x < 1_000;
  my $z = int(sqrt($x+0.5));
  my $a = _lehmer_pi(int(sqrt($z)+0.5));
  my $b = _lehmer_pi($z);
  my $c = _lehmer_pi(int($x**(1/3)+0.5));

  # Generate at least b primes.
  my $bth_prime_upper = ($b <= 10) ? 29 : int($b*(log($b) + log(log($b)))) + 1;
  my $primes = primes( $bth_prime_upper );

  my $sum = int(($b + $a - 2) * ($b - $a + 1) / 2);
  $sum += _legendre_phi($x, $a, $primes);

  # Get a big sieve for our primecounts.  The C code uses b*16 as a compromise,
  # as that cuts out all the inner loop sieves and about half the outer loop.
  # It also takes good advantage of segment sieving for the big outer counts.
  # We'll just go ahead and sieve everything we need now.  This is really much
  # more than we should use, but it saves a _huge_ amount of time given we're
  # not using a segment sieve for the outer loop.
  #my $sref = _sieve_erat($b * 16);
  my $sref = _sieve_erat( int($x / $primes->[$a]) );

  foreach my $i ($a+1 .. $b) {
    my $w = int($x / $primes->[$i-1]);
    $sum = $sum - _count_with_sieve($sref,$w);
    if ($i <= $c) {
      my $bi = _count_with_sieve($sref,int(sqrt($w)+0.5));
      foreach my $j ($i .. $bi) {
        $sum = $sum - _count_with_sieve($sref,int($w / $primes->[$j-1])) + $j - 1;
      }
    }
  }
  $sum;
}
#############################################################################


sub prime_count {
  my($low,$high) = @_;
  if (!defined $high) {
    $high = $low;
    $low = 2;
  }
  _validate_positive_integer($low);
  _validate_positive_integer($high);

  my $count = 0;

  $count++ if ($low <= 2) && ($high >= 2);   # Count 2
  $low = 3 if $low < 3;

  $low++ if ($low % 2) == 0;   # Make low go to odd number.
  $high-- if ($high % 2) == 0; # Make high go to odd number.
  return $count if $low > $high;

  if (   ref($low) eq 'Math::BigInt' || ref($high) eq 'Math::BigInt'
      || ($high-$low) < 10
      || ($high-$low) < int($low/100_000_000_000) ) {
    # Trial primes seems best.  Needs some tuning.
    my $curprime = next_prime($low-1);
    while ($curprime <= $high) {
      $count++;
      $curprime = next_prime($curprime);
    }
    return $count;
  }

  # TODO: Needs tuning
  if ($high > 50_000) {
    if ( ($high / ($high-$low+1)) < 100 ) {
      $count += _lehmer_pi($high);
      $count -= ($low == 3) ? 1 : _lehmer_pi($low-1);
      return $count;
    }
  }

  return (_sieve_prime_count($high) - 1 + $count) if $low == 3;

  my $sieveref = _sieve_segment($low,$high);
  $count += $$sieveref =~ tr/0//;
  return $count;
}


sub nth_prime {
  my($n) = @_;
  _validate_positive_integer($n);

  return $_primes_small[$n] if $n <= $#_primes_small;

  if (!defined $bigint::VERSION) { # This isn't ideal.
    if (_PP_prime_maxbits == 32) {
      croak "nth_prime($n) overflow" if $n > 203280221;
    } else {
      croak "nth_prime($n) overflow" if $n > 425656284035217743;
    }
  }

  my $prime = 0;

  my $count = 1;
  my $start = 3;

  my $logn = log($n);
  my $loglogn = log($logn);
  my $nth_prime_upper = ($n <= 10) ? 29 : int($n*($logn + $loglogn)) + 1;
  if ($nth_prime_upper > 100000) {
    # Use fast Lehmer prime count combined with lower bound to get close.
    my $nth_prime_lower = int($n * ($logn + $loglogn - 1.0 + (($loglogn-2.10)/$logn)));
    $nth_prime_lower-- unless $nth_prime_lower % 2;
    $count = _lehmer_pi($nth_prime_lower);
    $start = $nth_prime_lower + 2;
  }

  {
    # Make sure incr is an even number.
    my $incr = ($n < 1000) ? 1000 : ($n < 10000) ? 10000 : 100000;
    my $sieveref;
    while (1) {
      $sieveref = _sieve_segment($start, $start+$incr);
      my $segcount = $$sieveref =~ tr/0//;
      last if ($count + $segcount) >= $n;
      $count += $segcount;
      $start += $incr+2;
    }
    # Our count is somewhere in this segment.  Need to look for it.
    $prime = $start - 2;
    while ($count < $n) {
      $prime += 2;
      $count++ if !substr($$sieveref, ($prime-$start)>>1, 1);
    }
  }
  $prime;
}

sub _mulmod {
  my($a, $b, $m) = @_;
  return (($a * $b) % $m) if ($a|$b) < $_half_word;
  my $r = 0;
  while ($b > 0) {
    if ($b & 1) {
      if ($r == 0) {
        $r = $a;
      } else {
        $r = $m - $r;
        $r = ($a >= $r)  ?  $a - $r  :  $m - $r + $a;
      }
    }
    $a = ($a > ($m - $a))  ?  ($a - $m) + $a  :  $a + $a;
    $b >>= 1;
  }
  $r;
}

# Note that Perl 5.6.2 with largish 64-bit numbers will break.  As usual.
sub _native_powmod {
  my($n, $power, $m) = @_;
  my $t = 1;
  $n = $n % $m;
  while ($power) {
    $t = ($t * $n) % $m if ($power & 1);
    $power >>= 1;
    $n = ($n * $n) % $m if $power;
  }
  $t;
}

sub _powmod {
  my($n, $power, $m) = @_;
  my $t = 1;

  if  ($m < $_half_word) {
    $n %= $m;
    while ($power) {
      $t = ($t * $n) % $m if ($power & 1);
      $power >>= 1;
      $n = ($n * $n) % $m if $power;
    }
  } else {
    while ($power) {
      $t = _mulmod($t, $n, $m) if ($power & 1);
      $power >>= 1;
      $n = _mulmod($n, $n, $m) if $power;
    }
  }
  $t;
}

sub _gcd_ui {
  my($x, $y) = @_;
  if ($y < $x) { ($x, $y) = ($y, $x); }
  while ($y > 0) {
    # y1 <- x0 % y0 ; x1 <- y0
    my $t = $y;
    $y = $x % $y;
    $x = $t;
  }
  $x;
}

sub _is_perfect_power {
  my $n = shift;
  return 0 if $n <= 3 || $n != int($n);
  return 1 if ($n & ($n-1)) == 0;                       # Power of 2
  $n = Math::BigInt->new("$n") unless ref($n) eq 'Math::BigInt';
  # Perl 5.6.2 chokes on this, so do it via as_bin
  # my $log2n = 0; { my $num = $n; $log2n++ while $num >>= 1; }
  my $log2n = length($n->as_bin) - 2;
  for (my $e = 2; $e <= $log2n; $e = next_prime($e)) {
    return 1 if $n->copy()->broot($e)->bpow($e) == $n;
  }
  0;
}

sub _order {
  my($r, $n, $lim) = @_;
  $lim = $r unless defined $lim;

  return 1 if ($n % $r) == 1;
  for (my $j = 2; $j <= $lim; $j++) {
    return $j if _powmod($n, $j, $r) == 1;
  }
  return $lim+1;
}

# same result as:  int($n->blog(2)->floor->bstr)
sub _log2 {
  my $n = shift;
  my $log2n = 0;
  $log2n++ while ($n >>= 1);
  $log2n;
}



sub miller_rabin {
  my($n, @bases) = @_;
  _validate_positive_integer($n);
  croak "No bases given to miller_rabin" unless @bases;

  return 0 if ($n == 0) || ($n == 1);
  return 1 if ($n == 2) || ($n == 3);
  return 0 if !($n % 2);

  # Die on invalid bases
  do { croak "Base $_ is invalid" if $_ < 2 } for (@bases);
  # Make sure we handle big bases ok.
  @bases = grep { $_ > 1 }  map { ($_ >= $n) ? $_ % $n : $_ }  @bases;

  if ( ref($n) eq 'Math::BigInt' ) {

    my $s = 0;
    my $nminus1 = $n->copy->bsub(1);
    my $d = $nminus1->copy;
    while ($d->is_even) {
      $s++;
      $d->brsft(1);
    }

    foreach my $a (@bases) {
      my $x = $n->copy->bzero->badd($a)->bmodpow($d,$n);
      next if ($x->is_one) || ($x->bcmp($nminus1) == 0);
      foreach my $r (1 .. $s-1) {
        $x->bmul($x); $x->bmod($n);
        return 0 if $x->is_one;
        do { $a = 0; last; } if $x->bcmp($nminus1) == 0;
      }
      return 0 if $a != 0;
    }

  } else {

   my $s = 0;
   my $d = $n - 1;
   while ( ($d & 1) == 0 ) {
     $s++;
     $d >>= 1;
   }

   if ($n < $_half_word) {
    foreach my $a (@bases) {
      my $x = _native_powmod($a, $d, $n);
      next if ($x == 1) || ($x == ($n-1));
      foreach my $r (1 .. $s-1) {
        $x = ($x*$x) % $n;
        return 0 if $x == 1;
        last if $x == $n-1;
      }
      return 0 if $x != $n-1;
    }
   } else {
    foreach my $a (@bases) {
      my $x = _powmod($a, $d, $n);
      next if ($x == 1) || ($x == ($n-1));

      foreach my $r (1 .. $s-1) {
        $x = ($x < $_half_word) ? ($x*$x) % $n : _mulmod($x, $x, $n);
        return 0 if $x == 1;
        last if $x == $n-1;
      }
      return 0 if $x != $n-1;
    }
   }

  }
  1;
}

# Calculate Jacobi symbol (M|N)
sub _jacobi {
  my($n, $m) = @_;
  return 0 if $m <= 0 || ($m % 2) == 0;
  my $j = 1;
  if ($n < 0) {
    $n = -$n;
    $j = -$j if ($m % 4) == 3;
  }
  # Split loop so we can reduce n/m to non-bigints after first iteration.
  if ($n != 0) {
    while (($n % 2) == 0) {
      $n >>= 1;
      $j = -$j if ($m % 8) == 3 || ($m % 8) == 5;
    }
    ($n, $m) = ($m, $n);
    $j = -$j if ($n % 4) == 3 && ($m % 4) == 3;
    $n = $n % $m;
    $n = int($n->bstr) if $n <= ~0 && ref($n) eq 'Math::BigInt';
    $m = int($m->bstr) if $m <= ~0 && ref($m) eq 'Math::BigInt';
  }
  while ($n != 0) {
    while (($n % 2) == 0) {
      $n >>= 1;
      $j = -$j if ($m % 8) == 3 || ($m % 8) == 5;
    }
    ($n, $m) = ($m, $n);
    $j = -$j if ($n % 4) == 3 && ($m % 4) == 3;
    $n = $n % $m;
  }
  return ($m == 1) ? $j : 0;
}

# Find first D in sequence (5,-7,9,-11,13,-15,...) where (D|N) == -1
sub _find_jacobi_d_sequence {
  my($n) = @_;

  # D is typically quite small: 67 max for N < 10^19.  However, it is
  # theoretically possible D could grow unreasonably.  I'm giving up at 4000M.
  my $d = 5;
  my $sign = 1;
  while (1) {
    my $gcd = (ref($n) eq 'Math::BigInt') ? Math::BigInt::bgcd($d, $n)
                                          : _gcd_ui($d, $n);
    return 0 if $gcd > 1 && $gcd != $n;  # Found divisor $d
    my $j = _jacobi($d * $sign, $n);
    last if $j == -1;
    $d += 2;
    croak "Could not find Jacobi sequence for $n" if $d > 4_000_000_000;
    $sign = -$sign;
  }
  return ($sign * $d);
}


sub is_strong_lucas_pseudoprime {
  my($n) = @_;
  _validate_positive_integer($n);

  # We're trying to limit the bignum calculations as much as possible.
  # It's also important to try to match whatever they passed in.  For instance
  # if they use a GMP or Pari object, we must do the same.  Hence instead of:
  #        my $U = Math::BigInt->bone;
  # we do
  #        my $U = $n->copy->bone;
  # so U is the same class as n.  If they passed in a string or a small value,
  # then we just make it up.

  return 1 if $n == 2;
  return 0 if $n < 2 || ($n % 2) == 0;

  # References:
  #     http://www.trnicely.net/misc/bpsw.html
  #     Math::Primality

  # Check for perfect square
  if (ref($n) eq 'Math::BigInt') {
    my $mc = int(($n & 31)->bstr);
    if ($mc==0||$mc==1||$mc==4||$mc==9||$mc==16||$mc==17||$mc==25) {
      my $sq = $n->copy->bsqrt->bfloor;
      $sq->bmul($sq);
      return 0 if $sq == $n;
    }
  } else {
    my $mc = $n & 31;
    if ($mc==0||$mc==1||$mc==4||$mc==9||$mc==16||$mc==17||$mc==25) {
      my $sq = int(sqrt($n));
      return 0 if ($sq*$sq) == $n;
    }
  }

  # Determine Selfridge D, P, and Q parameters
  my $D = _find_jacobi_d_sequence($n);
  return 0 if $D == 0;  # We found a divisor in the sequence
  my $P = 1;
  my $Q = int( (1 - $D) / 4 );
  # Verify we've calculated this right
  die "Selfridge error: $D, $P, $Q\n" if ($D != $P*$P - 4*$Q);
  #warn "N: $n  D: $D  P: $P  Q: $Q\n";

  # It's now time to perform the Lucas pseudoprimality test using $D.

  if (ref($n) ne 'Math::BigInt') {
    if (!defined $MATH::BigInt::VERSION) {
      eval { require Math::BigInt;  Math::BigInt->import(try=>'GMP,Pari'); 1; }
      or do { croak "Cannot load Math::BigInt "; }
    }
    $n = Math::BigInt->new("$n");
  }

  my $m = $n->copy->badd(1);
  # Traditional d,s:
  #   my $d=$m->copy; my $s=0; while ($d->is_even) { $s++; $d->brsft(1); }
  #   die "Invalid $m, $d, $s\n" unless $m == $d * 2**$s;
  my $dstr = substr($m->as_bin, 2);
  $dstr =~ s/(0*)$//;
  my $s = length($1);

  my $ZERO = $n->copy->bzero;
  my $U = $ZERO + 1;
  my $V = $ZERO + $P;
  my $U_2m = $U->copy;
  my $V_2m = $V->copy;
  my $Q_m = $ZERO + $Q;
  my $Q_m2 = $Q_m->copy->bmul(2);
  my $Qkd = $Q_m->copy;
  substr($dstr,-1) = '';   #$d->brsft(1);
  #my $i = 1;
  while ($dstr ne '') {    #while (!$d->is_zero) {
    #warn "U=$U  V=$V  Qm=$Q_m  Qm2=$Q_m2\n";
    $U_2m->bmul($V_2m);             $U_2m->bmod($n);
    $V_2m->bmuladd($V_2m, -$Q_m2);  $V_2m->bmod($n);
    #warn "  $i  U2m=$U_2m  V2m=$V_2m\n";  $i++;
    $Q_m->bmul($Q_m);               $Q_m->bmod($n);
    $Q_m2 = $Q_m->copy->bmul(2);    # no mod
    if (substr($dstr,-1)) {   #if ($d->is_odd) {
      my $T1 = $U_2m->copy->bmul($V);
      my $T2 = $U_2m->copy->bmul($U)->bmul($D);
      $U->bmuladd($V_2m, $T1);         # U = U*V_2m + V*U_2m
      $U->badd($n) if $U->is_odd;      # U += n if U & 1
      $U->brsft(1,2);                  # U = floor(U / 2)
      $U->bmod($n);                    # U = U % n

      $V->bmuladd($V_2m, $T2);
      $V->badd($n) if $V->is_odd;
      $V->brsft(1,2);
      $V->bmod($n);

      $Qkd->bmul($Q_m);
      $Qkd->bmod($n);
    }
    substr($dstr,-1) = '';   #$d->brsft(1);
  }
  #warn "l0 U=$U  V=$V\n";
  return 1 if $U->is_zero || $V->is_zero;

  # Compute powers of V
  my $Qkd2 = $Qkd->copy->bmul(2);
  foreach my $r (1 .. $s-1) {
    #warn "l$r U=$U  V=$V  Qkd2=$Qkd2\n";
    $V->bmuladd($V, -$Qkd2);  $V->bmod($n);
    return 1 if $V->is_zero;
    if ($r < ($s-1)) {
      $Qkd->bmul($Qkd);  $Qkd->bmod($n);
      $Qkd2 = $Qkd->copy->bmul(2);
    }
  }
  return 0;
}


my $_poly_bignum;
sub _poly_new {
  my @poly;
  if ($_poly_bignum) {
    foreach my $c (@_) {
      push @poly, (ref $c eq 'Math::BigInt') ? $c->copy : Math::BigInt->new("$c");
    }
  } else {
    push @poly, $_ for (@_);
    push @poly, 0 unless scalar @poly;
  }
  return \@poly;
}

sub _poly_print {
  my($poly) = @_;
  warn "poly has null top degree" if $#$poly > 0 && !$poly->[-1];
  foreach my $d (reverse 1 .. $#$poly) {
    my $coef = $poly->[$d];
    print "", ($coef != 1) ? $coef : "", ($d > 1) ? "x^$d" : "x", " + "
      if $coef;
  }
  my $p0 = $poly->[0] || 0;
  print "$p0\n";
}

sub _poly_mod_mul {
  my($px, $py, $r, $n) = @_;

  my $px_degree = $#$px;
  my $py_degree = $#$py;
  my @res;

  # convolve(px, py) mod (X^r-1,n)
  my @indices_y = grep { $py->[$_] } (0 .. $py_degree);
  for (my $ix = 0; $ix <= $px_degree; $ix++) {
    my $px_at_ix = $px->[$ix];
    next unless $px_at_ix;
    if ($_poly_bignum) {
      foreach my $iy (@indices_y) {
        my $rindex = ($ix + $iy) % $r;  # reduce mod X^r-1
        $res[$rindex] = Math::BigInt->bzero unless defined $res[$rindex];
        $res[$rindex]->badd($px_at_ix->copy->bmul($py->[$iy]))->bmod($n);
      }
    } else {
      foreach my $iy (@indices_y) {
        my $rindex = ($ix + $iy) % $r;  # reduce mod X^r-1
        $res[$rindex] = 0 unless defined $res[$rindex];
        my $py_px = $px_at_ix * $py->[$iy];
        $res[$rindex] = ($res[$rindex] + $py_px) % $n;
      }
    }
  }
  # In case we had upper terms go to zero after modulo, reduce the degree.
  pop @res while !$res[-1];
  return \@res;
}

sub _poly_mod_pow {
  my($pn, $power, $r, $mod) = @_;
  my $res = _poly_new(1);
  my $p = $power;

  while ($p) {
    $res = _poly_mod_mul($res, $pn, $r, $mod) if ($p & 1);
    $p >>= 1;
    $pn  = _poly_mod_mul($pn,  $pn, $r, $mod) if $p;
  }
  return $res;
}

sub _test_anr {
  my($a, $n, $r) = @_;
  my $pp = _poly_mod_pow(_poly_new($a, 1), $n, $r, $n);
  $pp->[$n % $r] = (($pp->[$n % $r] || 0) -  1) % $n;  # subtract X^(n%r)
  $pp->[      0] = (($pp->[      0] || 0) - $a) % $n;  # subtract a
  return 0 if scalar grep { $_ } @$pp;
  1;
}

sub is_aks_prime {
  my $n = shift;

  if (!defined $MATH::BigInt::VERSION) {
    eval { require Math::BigInt;  Math::BigInt->import(try=>'GMP,Pari'); 1; }
    or do { croak "Cannot load Math::BigInt "; }
  }
  if (!defined $MATH::BigFloat::VERSION) {
    eval { require Math::BigFloat;   Math::BigFloat->import(); 1; }
    or do { croak "Cannot load Math::BigFloat "; }
  }
  $n = Math::BigInt->new("$n") unless ref($n) eq 'Math::BigInt';

  return 0 if $n < 2;
  return 0 if _is_perfect_power($n);

  # limit = floor( log2(n) * log2(n) ).  o_r(n) must be larger than this
  my $sqrtn = int(Math::BigFloat->new($n)->bsqrt->bfloor->bstr);
  my $log2n = Math::BigFloat->new("$n")->blog(2);
  my $log2_squared_n = $log2n * $log2n;
  my $limit = int($log2_squared_n->bfloor->bstr);

  my $r = next_prime($limit);
  foreach my $f (@{primes(0,$r-1)}) {
    return 1 if $f == $n;
    return 0 if !($n % $f);
  }

  while ($r < $n) {
    return 0 if !($n % $r);
    #return 1 if $r >= $sqrtn;
    last if _order($r, $n, $limit) > $limit;
    $r = next_prime($r);
  }

  return 1 if $r >= $n;

  # Since r is a prime, phi(r) = r-1
  my $rlimit = int( Math::BigFloat->new("$r")->bsub(1)
                    ->bsqrt->bmul($log2n)->bfloor->bstr);

  $_poly_bignum = 1;
  if ( $n < ( (~0 == 4294967295) ? 65535 : 4294967295 ) ) {
    $_poly_bignum = 0;
    $n = int($n->bstr) if ref($n) eq 'Math::BigInt';
  }

  for (my $a = 1; $a <= $rlimit; $a++) {
    return 0 unless _test_anr($a, $n, $r);
  }

  return 1;
}


sub _basic_factor {
  # MODIFIES INPUT SCALAR
  return ($_[0]) if $_[0] < 4;

  my @factors;
  if (ref($_[0]) ne 'Math::BigInt') {
    while ( !($_[0] % 2) ) { push @factors, 2;  $_[0] = int($_[0] / 2); }
    while ( !($_[0] % 3) ) { push @factors, 3;  $_[0] = int($_[0] / 3); }
    while ( !($_[0] % 5) ) { push @factors, 5;  $_[0] = int($_[0] / 5); }
  } else {
    if (Math::BigInt::bgcd($_[0], 2*3*5) != 1) {
      while ( $_[0]->is_even)   { push @factors, 2;  $_[0]->brsft(1); }
      foreach my $div (3, 5) {
        my ($q, $r) = $_[0]->copy->bdiv($div);
        while ($r->is_zero) {
          push @factors, $div;
          $_[0] = $q;
          ($q, $r) = $_[0]->copy->bdiv($div);
        }
      }
    }
    $_[0] = int($_[0]->bstr) if $_[0] <= ~0;
  }

  if ( ($_[0] > 1) && _is_prime7($_[0]) ) {
    push @factors, $_[0];
    $_[0] = 1;
  }
  @factors;
}

sub trial_factor {
  my($n) = @_;
  _validate_positive_integer($n);

  my @factors = _basic_factor($n);
  return @factors if $n < 4;

  my $limit = int( sqrt($n) + 0.001);
  my $f = 3;
  while ($f <= $limit) {
    if ( ($n % $f) == 0) {
      while ( ($n % $f) == 0) {
        push @factors, $f;
        $n = int($n/$f);
      }
      $limit = int( sqrt($n) + 0.001);
    }
    $f += 2;
  }
  push @factors, $n  if $n > 1;
  @factors;
}

sub factor {
  my($n) = @_;
  _validate_positive_integer($n);
  $n = $n->copy if ref($n) eq 'Math::BigInt';

  return trial_factor($n) if $n < 100000;

  my @factors = _basic_factor($n);
  return @factors if $n < 4;

  # Use 'n = int($n/7)' instead of 'n/=7' to not "upgrade" n to a Math::BigFloat.
  while (($n %  7) == 0) { push @factors,  7;  $n = int($n /  7); }
  while (($n % 11) == 0) { push @factors, 11;  $n = int($n / 11); }
  while (($n % 13) == 0) { push @factors, 13;  $n = int($n / 13); }
  while (($n % 17) == 0) { push @factors, 17;  $n = int($n / 17); }
  while (($n % 19) == 0) { push @factors, 19;  $n = int($n / 19); }
  while (($n % 23) == 0) { push @factors, 23;  $n = int($n / 23); }
  while (($n % 29) == 0) { push @factors, 29;  $n = int($n / 29); }
  if ($n < (31*31)) {
    push @factors, $n  if $n != 1;
    return @factors;
  }

  my @nstack = ($n);
  while (@nstack) {
    $n = pop @nstack;
    # Don't use bignum on $n if it has gotten small enough.
    $n = int($n->bstr) if ref($n) eq 'Math::BigInt' && $n <= ~0;
    #print "Looking at $n with stack ", join(",",@nstack), "\n";
    while ( ($n >= (31*31)) && !_is_prime7($n) ) {
      my @ftry;
      my $holf_rounds = 0;
      if ($n < $_half_word) {
        $holf_rounds = 64*1024;
        #warn "trying holf 64k on $n\n";
        @ftry = holf_factor($n, $holf_rounds);
      }
      if (scalar @ftry < 2) {
        foreach my $add (3, 5, 7, 11, 13) {
          #warn "trying prho 64k {$add} on $n\n" if scalar @ftry < 2;
          @ftry = prho_factor($n, 64*1024, $add) if scalar @ftry < 2;
        }
      }
      if (scalar @ftry < 2) {
        #warn "trying holf 128k on $n\n";
        @ftry = holf_factor($n, 128*1024, $holf_rounds);
        $holf_rounds += 128*1024;
      }
      if (scalar @ftry < 2) {
        #warn "trying prho 128k {17} on $n\n";
        @ftry = prho_factor($n, 128*1024, 17);
      }
      if (scalar @ftry > 1) {
        #print "  split into ", join(",",@ftry), "\n";
        $n = shift @ftry;
        push @nstack, @ftry;
      } else {
        #warn "trial factor $n\n";
        push @factors, trial_factor($n);
        #print "  trial into ", join(",",@factors), "\n";
        $n = 1;
        last;
      }
    }
    push @factors, $n  if $n != 1;
  }
  sort {$a<=>$b} @factors;
}

# TODO:
sub fermat_factor { trial_factor(@_) }
sub squfof_factor { trial_factor(@_) }

sub prho_factor {
  my($n, $rounds, $a) = @_;
  _validate_positive_integer($n);
  $rounds = 4*1024*1024 unless defined $rounds;
  $a = 3 unless defined $a;

  my @factors = _basic_factor($n);
  return @factors if $n < 4;

  my $inloop = 0;
  my $U = 7;
  my $V = 7;

  if ( ref($n) eq 'Math::BigInt' ) {

    $U = $n->copy->bzero->badd($U);
    $V = $n->copy->bzero->badd($V);
    for my $i (1 .. $rounds) {
      # Would use bmuladd here, but old Math::BigInt's barf with scalar $a.
      #$U->bmuladd($U, $a);  $U->bmod($n);
      #$V->bmuladd($V, $a);  $V->bmod($n);
      #$V->bmuladd($V, $a);  $V->bmod($n);
      $U->bmul($U); $U->badd($a); $U->bmod($n);
      $V->bmul($V); $V->badd($a); $V->bmod($n);
      $V->bmul($V); $V->badd($a); $V->bmod($n);
      my $f = Math::BigInt::bgcd( ($U > $V) ? $U-$V : $V-$U,  $n);
      if ($f == $n) {
        last if $inloop++;  # We've been here before
      } elsif ($f != 1) {
        my $f2 = $n->copy->bdiv($f)->as_int;
        push @factors, $f;
        push @factors, $f2;
        croak "internal error in prho" unless ($f * $f2) == $n;
        return @factors;
      }
    }

  } elsif ($n < $_half_word) {

    for my $i (1 .. $rounds) {
      $U = ($U * $U + $a) % $n;
      $V = ($V * $V + $a) % $n;
      $V = ($V * $V + $a) % $n;
      my $f = _gcd_ui( ($U > $V) ? $U-$V : $V-$U,  $n );
      if ($f == $n) {
        last if $inloop++;  # We've been here before
      } elsif ($f != 1) {
        push @factors, $f;
        push @factors, int($n/$f);
        croak "internal error in prho" unless ($f * int($n/$f)) == $n;
        return @factors;
      }
    }

  } else {

    for my $i (1 .. $rounds) {
      # U^2+a % n
      $U = _mulmod($U, $U, $n);
      $U = (($n-$U) > $a)  ?  $U+$a  :  $U+$a-$n;
      # V^2+a % n
      $V = _mulmod($V, $V, $n);
      $V = (($n-$V) > $a)  ?  $V+$a  :  $V+$a-$n;
      # V^2+a % n
      $V = _mulmod($V, $V, $n);
      $V = (($n-$V) > $a)  ?  $V+$a  :  $V+$a-$n;
      my $f = _gcd_ui( ($U > $V) ? $U-$V : $V-$U,  $n );
      if ($f == $n) {
        last if $inloop++;  # We've been here before
      } elsif ($f != 1) {
        push @factors, $f;
        push @factors, int($n/$f);
        croak "internal error in prho" unless ($f * int($n/$f)) == $n;
        return @factors;
      }
    }

  }
  push @factors, $n;
  @factors;
}

sub pbrent_factor {
  my($n, $rounds) = @_;
  _validate_positive_integer($n);
  $rounds = 4*1024*1024 unless defined $rounds;

  my @factors = _basic_factor($n);
  return @factors if $n < 4;

  my $a = 1;
  my $Xi = 2;
  my $Xm = 2;

  if ( ref($n) eq 'Math::BigInt' ) {

    $Xi = $n->copy->bzero->badd($Xi);
    $Xm = $n->copy->bzero->badd($Xm);
    for my $i (1 .. $rounds) {
      $Xi->bmul($Xi);  $Xi->badd($a);  $Xi->bmod($n);
      my $f = Math::BigInt::bgcd( ($Xi > $Xm) ? $Xi-$Xm : $Xm-$Xi,  $n);
      if ( ($f != 1) && ($f != $n) ) {
        my $f2 = $n->copy->bdiv($f)->as_int;
        push @factors, $f;
        push @factors, $f2;
        croak "internal error in pbrent" unless ($f * $f2) == $n;
        return @factors;
      }
      $Xm = $Xi->copy if ($i & ($i-1)) == 0;  # i is a power of 2
    }

  } elsif ($n < $_half_word) {

    for my $i (1 .. $rounds) {
      $Xi = ($Xi * $Xi + $a) % $n;
      my $f = _gcd_ui( ($Xi > $Xm) ? $Xi-$Xm : $Xm-$Xi,  $n );
      if ( ($f != 1) && ($f != $n) ) {
        push @factors, $f;
        push @factors, int($n/$f);
        croak "internal error in pbrent" unless ($f * int($n/$f)) == $n;
        return @factors;
      }
      $Xm = $Xi if ($i & ($i-1)) == 0;  # i is a power of 2
    }

  } else {

    for my $i (1 .. $rounds) {
      # Xi^2+a % n
      $Xi = _mulmod($Xi, $Xi, $n);
      $Xi = (($n-$Xi) > $a)  ?  $Xi+$a  :  $Xi+$a-$n;
      my $f = _gcd_ui( ($Xi > $Xm) ? $Xi-$Xm : $Xm-$Xi,  $n );
      if ( ($f != 1) && ($f != $n) ) {
        push @factors, $f;
        push @factors, int($n/$f);
        croak "internal error in pbrent" unless ($f * int($n/$f)) == $n;
        return @factors;
      }
      $Xm = $Xi if ($i & ($i-1)) == 0;  # i is a power of 2
    }

  }
  push @factors, $n;
  @factors;
}

# This code is bollocks.  See a proper implementation in factor.c
sub pminus1_factor {
  my($n, $rounds) = @_;
  _validate_positive_integer($n);
  $rounds = 4*1024*1024 unless defined $rounds;

  my @factors = _basic_factor($n);
  return @factors if $n < 4;

  if ( ref($n) eq 'Math::BigInt' ) {
    my $kf = $n->copy->bzero->badd(13);
    for my $i (1 .. $rounds) {
      $kf->bmodpow($i,$n);
      $kf = $n if $kf == 0;
      my $f = Math::BigInt::bgcd( $kf-1, $n );
      if ( ($f != 1) && ($f != $n) ) {
        my $f2 = $n->copy->bdiv($f)->as_int;
        push @factors, $f;
        push @factors, $f2;
        croak "internal error in pminus1" unless ($f * $f2) == $n;
        return @factors;
      }
    }
  } else {
    my $kf = 13;
    for my $i (1 .. $rounds) {
      $kf = _powmod($kf, $i, $n);
      $kf = $n if $kf == 0;
      my $f = _gcd_ui( $kf-1, $n );
      if ( ($f != 1) && ($f != $n) ) {
        push @factors, $f;
        push @factors, int($n/$f);
        croak "internal error in pminus1" unless ($f * int($n/$f)) == $n;
        return @factors;
      }
    }
  }
  push @factors, $n;
  @factors;
}

sub holf_factor {
  my($n, $rounds, $startrounds) = @_;
  _validate_positive_integer($n);
  $rounds = 64*1024*1024 unless defined $rounds;
  $startrounds = 1 unless defined $startrounds;

  my @factors = _basic_factor($n);
  return @factors if $n < 4;

  if ( ref($n) eq 'Math::BigInt' ) {
    for my $i ($startrounds .. $rounds) {
      my $ni = $n->copy->bmul($i);
      my $s = $ni->copy->bsqrt->bfloor->as_int;
      $s->binc if ($s * $s) != $ni;
      my $m = $s->copy->bmul($s)->bmod($n);
      # Check for perfect square
      my $mc = int(($m & 31)->bstr);
      next unless $mc==0||$mc==1||$mc==4||$mc==9||$mc==16||$mc==17||$mc==25;
      my $f = $m->copy->bsqrt->bfloor->as_int;
      next unless ($f*$f) == $m;
      $f = Math::BigInt::bgcd( ($s > $f) ? $s-$f : $f-$s,  $n);
      last if $f == 1 || $f == $n;   # Should never happen
      my $f2 = $n->copy->bdiv($f)->as_int;
      push @factors, $f;
      push @factors, $f2;
      croak "internal error in HOLF" unless ($f * $f2) == $n;
      # print "HOLF found factors in $i rounds\n";
      return @factors;
    }
  } else {
    for my $i ($startrounds .. $rounds) {
      my $s = int(sqrt($n * $i));
      $s++ if ($s * $s) != ($n * $i);
      my $m = ($s < $_half_word) ? ($s*$s) % $n : _mulmod($s, $s, $n);
      # Check for perfect square
      my $mc = $m & 31;
      next unless $mc==0||$mc==1||$mc==4||$mc==9||$mc==16||$mc==17||$mc==25;
      my $f = int(sqrt($m));
      next unless $f*$f == $m;
      $f = _gcd_ui( ($s > $f)  ?  $s - $f  :  $f - $s,  $n);
      last if $f == 1 || $f == $n;   # Should never happen
      push @factors, $f;
      push @factors, int($n/$f);
      croak "internal error in HOLF" unless ($f * int($n/$f)) == $n;
      # print "HOLF found factors in $i rounds\n";
      return @factors;
    }
  }
  push @factors, $n;
  @factors;
}




my $_const_euler = 0.57721566490153286060651209008240243104215933593992;
my $_const_li2 = 1.045163780117492784844588889194613136522615578151;

sub ExponentialIntegral {
  my($x) = @_;
  return $_Neg_Infinity if $x == 0;
  return 0              if $x == $_Neg_Infinity;
  return $_Infinity     if $x == $_Infinity;

  # Use MPFR if possible.
  if ($_have_MPFR < 0) {
    $_have_MPFR = 0;
    $_have_MPFR = 1 if (!defined $ENV{MPU_NO_MPFR} || $ENV{MPU_NO_MPFR} != 1)
                    && eval { require Math::MPFR; $Math::MPFR::VERSION>=2.03; };
  }
  # Gotcha -- MPFR decided to make negative inputs return NaN.  Grrr.
  if ($_have_MPFR && $x > 0) {
    my $wantbf = 0;
    my $xdigits = 17;
    if (defined $bignum::VERSION || ref($x) =~ /^Math::Big/) {
      if (!defined $MATH::BigFloat::VERSION) {
        eval { require Math::BigFloat;   Math::BigFloat->import(); 1; }
        or do { croak "Cannot load Math::BigFloat "; }
      }
      $x = new Math::BigFloat "$x" if ref($x) ne 'Math::BigFloat';
      $wantbf = 1;
      $xdigits = $x->accuracy || Math::BigFloat->accuracy() || Math::BigFloat->div_scale();
    }
    my $rnd = 0;  # MPFR_RNDN;
    my $bit_precision = int($xdigits * 3.322) + 4;
    my $rx = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rx, $bit_precision);
    Math::MPFR::Rmpfr_set_str($rx, "$x", 10, $rnd);
    my $eix = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($eix, $bit_precision);
    Math::MPFR::Rmpfr_eint($eix, $rx, $rnd);
    my $strval = Math::MPFR::Rmpfr_get_str($eix, 10, 0, $rnd);
    return ($wantbf)  ?  Math::BigFloat->new($strval)  :  0.0 + $strval;
  }

  $x = new Math::BigFloat "$x"  if defined $bignum::VERSION && ref($x) ne 'Math::BigFloat';

  my $tol = 1e-16;
  my $sum = 0.0;
  my($y, $t);
  my $c = 0.0;
  my $val; # The result from one of the four methods

  if ($x < -1) {
    # Continued fraction
    my $lc = 0;
    my $ld = 1 / (1 - $x);
    $val = $ld * (-exp($x));
    for my $n (1 .. 100000) {
      $lc = 1 / (2*$n + 1 - $x - $n*$n*$lc);
      $ld = 1 / (2*$n + 1 - $x - $n*$n*$ld);
      my $old = $val;
      $val *= $ld/$lc;
      last if abs($val - $old) <= ($tol * abs($val));
    }
  } elsif ($x < 0) {
    # Rational Chebyshev approximation
    my @C6p = ( -148151.02102575750838086,
                 150260.59476436982420737,
                  89904.972007457256553251,
                  15924.175980637303639884,
                   2150.0672908092918123209,
                    116.69552669734461083368,
                      5.0196785185439843791020);
    my @C6q = (  256664.93484897117319268,
                 184340.70063353677359298,
                  52440.529172056355429883,
                   8125.8035174768735759866,
                    750.43163907103936624165,
                     40.205465640027706061433,
                      1.0000000000000000000000);
    my $sumn = $C6p[0]-$x*($C6p[1]-$x*($C6p[2]-$x*($C6p[3]-$x*($C6p[4]-$x*($C6p[5]-$x*$C6p[6])))));
    my $sumd = $C6q[0]-$x*($C6q[1]-$x*($C6q[2]-$x*($C6q[3]-$x*($C6q[4]-$x*($C6q[5]-$x*$C6q[6])))));
    $val = log(-$x) - ($sumn / $sumd);
  } elsif ($x < -log($tol)) {
    # Convergent series
    my $fact_n = 1;
    $y = $_const_euler-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
    $y = log($x)-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
    for my $n (1 .. 200) {
      $fact_n *= $x/$n;
      my $term = $fact_n / $n;
      $y = $term-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
      last if $term < $tol;
    }
    $val = $sum;
  } else {
    # Asymptotic divergent series
    my $invx = 1.0 / $x;
    my $term = $invx;
    $sum = 1.0 + $term;
    for my $n (2 .. 200) {
      my $last_term = $term;
      $term *= $n * $invx;
      last if $term < $tol;
      if ($term < $last_term) {
        $y = $term-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
      } else {
        $y = (-$last_term/3)-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
        last;
      }
    }
    $val = exp($x) * $invx * $sum;
  }
  $val;
}

sub LogarithmicIntegral {
  my($x) = @_;
  return 0              if $x == 0;
  return $_Neg_Infinity if $x == 1;
  return $_Infinity     if $x == $_Infinity;
  croak "Invalid input to LogarithmicIntegral:  x must be > 0" if $x <= 0;

  # Use MPFR if possible.
  if ($_have_MPFR < 0) {
    $_have_MPFR = 0;
    $_have_MPFR = 1 if (!defined $ENV{MPU_NO_MPFR} || $ENV{MPU_NO_MPFR} != 1)
                    && eval { require Math::MPFR; $Math::MPFR::VERSION>=2.03; };
  }
  # Remember MPFR eint doesn't handle negative inputs
  if ($_have_MPFR && $x >= 1) {
    my $wantbf = 0;
    my $xdigits = 17;
    if (defined $bignum::VERSION || ref($x) =~ /^Math::Big/) {
      if (!defined $MATH::BigFloat::VERSION) {
        eval { require Math::BigFloat;   Math::BigFloat->import(); 1; }
        or do { croak "Cannot load Math::BigFloat "; }
      }
      $x = new Math::BigFloat "$x" if ref($x) ne 'Math::BigFloat';
      $wantbf = 1;
      $xdigits = $x->accuracy || Math::BigFloat->accuracy() || Math::BigFloat->div_scale();
    }
    $x = log($x); # Use BigFloat to do the log to simplify precision tracking.
    my $rnd = 0;  # MPFR_RNDN;
    my $bit_precision = int($xdigits * 3.322) + 4;
    my $rx = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rx, $bit_precision);
    Math::MPFR::Rmpfr_set_str($rx, "$x", 10, $rnd);
    my $lix = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($lix, $bit_precision);
    Math::MPFR::Rmpfr_eint($lix, $rx, $rnd);
    my $strval = Math::MPFR::Rmpfr_get_str($lix, 10, 0, $rnd);
    return ($wantbf)  ?  Math::BigFloat->new($strval)  :  0.0 + $strval;
  }

  if ($x == 2) {
    my $li2const = (ref($x) eq 'Math::BigFloat') ? Math::BigFloat->new('1.04516378011749278484458888919461313652261557815120157583290914407501320521') : $_const_li2;
    return $li2const;
  }

  $x = new Math::BigFloat "$x" if defined $bignum::VERSION && ref($x) ne 'Math::BigFloat';
  my $logx = log($x);

  # Do divergent series here for big inputs.  Common for big pc approximations.
  # Why is this here?
  #   1) exp(log(x)) results in a lot of lost precision
  #   2) exp(x) with lots of precision turns out to be really slow, and in
  #      this case it was unnecessary.
  if ($x > 1e16) {
    my $tol = 1e-20;
    my $invx = 1.0 / $logx;
    # n = 0  =>  0!/(logx)^0 = 1/1 = 1
    # n = 1  =>  1!/(logx)^1 = 1/logx
    my $term = $invx;
    my $sum = 1.0 + $term;
    for my $n (2 .. 200) {
      my $last_term = $term;
      $term *= $n * $invx;
      last if $term < $tol;
      if ($term < $last_term) {
        $sum += $term;
      } else {
        $sum -= ($last_term/3);
        last;
      }
    }
    my $val = $x * $invx * $sum;
    return $val;
  }
  # Convergent series.
  if ($x >= 1) {
    my $tol  = 1e-20;
    my $fact_n = 1.0;
    my $nfac = 1.0;
    my $sum  = 0.0;
    for my $n (1 .. 200) {
      $fact_n *= $logx/$n;
      my $term = $fact_n / $n;
      $sum += $term;
      last if $term < $tol;
    }
    my $eulerconst = (ref($x) eq 'Math::BigFloat') ? Math::BigFloat->new('0.577215664901532860606512090082402431042159335939923598805767') : $_const_euler;
    my $val = $eulerconst + log($logx) + $sum;
    return $val;
  }

  ExponentialIntegral($logx);
}

# Riemann Zeta function for native integers.
my @_Riemann_Zeta_Table = (
  0.6449340668482264364724151666460251892,  # zeta(2) - 1
  0.2020569031595942853997381615114499908,
  0.0823232337111381915160036965411679028,
  0.0369277551433699263313654864570341681,
  0.0173430619844491397145179297909205279,
  0.0083492773819228268397975498497967596,
  0.0040773561979443393786852385086524653,
  0.0020083928260822144178527692324120605,
  0.0009945751278180853371459589003190170,
  0.0004941886041194645587022825264699365,
  0.0002460865533080482986379980477396710,
  0.0001227133475784891467518365263573957,
  0.0000612481350587048292585451051353337,
  0.0000305882363070204935517285106450626,
  0.0000152822594086518717325714876367220,
  0.0000076371976378997622736002935630292,
  0.0000038172932649998398564616446219397,
  0.0000019082127165539389256569577951013,
  0.0000009539620338727961131520386834493,
  0.0000004769329867878064631167196043730,
  0.0000002384505027277329900036481867530,
  0.0000001192199259653110730677887188823,
  0.0000000596081890512594796124402079358,
  0.0000000298035035146522801860637050694,
  0.0000000149015548283650412346585066307,
  0.0000000074507117898354294919810041706,
  0.0000000037253340247884570548192040184,
  0.0000000018626597235130490064039099454,
  0.0000000009313274324196681828717647350,
  0.0000000004656629065033784072989233251,
  0.0000000002328311833676505492001455976,
  0.0000000001164155017270051977592973835,
  0.0000000000582077208790270088924368599,
  0.0000000000291038504449709968692942523,
  0.0000000000145519218910419842359296322,
  0.0000000000072759598350574810145208690,
  0.0000000000036379795473786511902372363,
  0.0000000000018189896503070659475848321,
  0.0000000000009094947840263889282533118,
);


sub RiemannZeta {
  my($x) = @_;

  # Use MPFR if possible.
  if ($_have_MPFR < 0) {
    $_have_MPFR = 0;
    $_have_MPFR = 1 if (!defined $ENV{MPU_NO_MPFR} || $ENV{MPU_NO_MPFR} != 1)
                    && eval { require Math::MPFR; $Math::MPFR::VERSION>=2.03; };
  }
  if ($_have_MPFR) {
    my $wantbf = 0;
    my $xdigits = 17;
    if (defined $bignum::VERSION || ref($x) =~ /^Math::Big/) {
      if (!defined $MATH::BigFloat::VERSION) {
        eval { require Math::BigFloat;   Math::BigFloat->import(); 1; }
        or do { croak "Cannot load Math::BigFloat "; }
      }
      $x = new Math::BigFloat "$x" if ref($x) ne 'Math::BigFloat';
      $wantbf = 1;
      $xdigits = $x->accuracy || Math::BigFloat->accuracy() || Math::BigFloat->div_scale();
    }
    my $rnd = 0;  # MPFR_RNDN;
    my $bit_precision = int($xdigits * 3.322) + 4;
    my $rx = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rx, $bit_precision);
    Math::MPFR::Rmpfr_set_str($rx, "$x", 10, $rnd);
    my $zetax = Math::MPFR->new();
    # Add more bits to account for the leading zeros.
    my $extra_bits = int(abs($x));
    Math::MPFR::Rmpfr_set_prec($zetax, $bit_precision + $extra_bits);
    Math::MPFR::Rmpfr_zeta($zetax, $rx, $rnd);
    Math::MPFR::Rmpfr_sub_ui($zetax, $zetax, 1, $rnd);
    my $strval = Math::MPFR::Rmpfr_get_str($zetax, 10, $xdigits, $rnd);
    return ($wantbf)  ?  Math::BigFloat->new($strval)  :  0.0 + $strval;
  }

  if (defined $bignum::VERSION || ref($x) =~ /^Math::Big/) {
    # No MPFR, BigFloat
    require Math::Prime::Util::ZetaBigFloat;
    return Math::Prime::Util::ZetaBigFloat::RiemannZeta($x);
  }

  # No MPFR, no BigFloat.
  return 0.0 + $_Riemann_Zeta_Table[int($x)-2]
    if $x == int($x) && defined $_Riemann_Zeta_Table[int($x)-2];
  my $tol = 1e-16;
  my($y, $t);
  my $sum = 0.0;
  my $c = 0.0;

  for my $k (2 .. 1000000) {
    my $term = (2*$k+1) ** -$x;
    $y = $term-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
    last if $term < abs($tol*$sum);
  }
  my $term = 3 ** -$x;
  $y = $term-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
  $t = 1.0 / (1.0 - (2 ** -$x));
  $sum *= $t;
  $sum += ($t - 1.0);
  return $sum;
}

# Riemann R function
sub RiemannR {
  my($x) = @_;

  croak "Invalid input to ReimannR:  x must be > 0" if $x <= 0;

  # Use MPFR if possible.
  if ($_have_MPFR < 0) {
    $_have_MPFR = 0;
    $_have_MPFR = 1 if (!defined $ENV{MPU_NO_MPFR} || $ENV{MPU_NO_MPFR} != 1)
                    && eval { require Math::MPFR; $Math::MPFR::VERSION>=2.03; };
  }
  if ($_have_MPFR) {
    my $wantbf = 0;
    my $xdigits = 17;
    if (defined $bignum::VERSION || ref($x) =~ /^Math::Big/) {
      if (!defined $MATH::BigFloat::VERSION) {
        eval { require Math::BigFloat;   Math::BigFloat->import(); 1; }
        or do { croak "Cannot load Math::BigFloat "; }
      }
      $x = new Math::BigFloat "$x" if ref($x) ne 'Math::BigFloat';
      $wantbf = 1;
      $xdigits = $x->accuracy || Math::BigFloat->accuracy() || Math::BigFloat->div_scale();
    }
    my $rnd = 0;  # MPFR_RNDN;
    my $bit_precision = int($xdigits * 3.322) + 8;  # Add some extra

    my $rlogx = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rlogx, $bit_precision);
    Math::MPFR::Rmpfr_set_str($rlogx, "$x", 10, $rnd);
    Math::MPFR::Rmpfr_log($rlogx, $rlogx, $rnd);

    my $rpart_term = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rpart_term, $bit_precision);
    Math::MPFR::Rmpfr_set_str($rpart_term, "1", 10, $rnd);

    my $rzeta = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rzeta, $bit_precision);
    my $rterm = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rterm, $bit_precision);

    my $rsum = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rsum, $bit_precision);
    Math::MPFR::Rmpfr_set_str($rsum, "1", 10, $rnd);

    my $rstop = Math::MPFR->new();
    Math::MPFR::Rmpfr_set_prec($rstop, $bit_precision);
    Math::MPFR::Rmpfr_set_str($rstop, "1e-$xdigits", 10, $rnd);

    for my $k (1 .. 10000) {
      Math::MPFR::Rmpfr_mul($rpart_term, $rpart_term, $rlogx, $rnd);
      Math::MPFR::Rmpfr_div_ui($rpart_term, $rpart_term, $k, $rnd);

      Math::MPFR::Rmpfr_zeta_ui($rzeta, $k+1, $rnd);
      Math::MPFR::Rmpfr_sub_ui($rzeta, $rzeta, 1, $rnd);
      Math::MPFR::Rmpfr_mul_ui($rzeta, $rzeta, $k, $rnd);
      Math::MPFR::Rmpfr_add_ui($rzeta, $rzeta, $k, $rnd);
      Math::MPFR::Rmpfr_div($rterm, $rpart_term, $rzeta, $rnd);

      last if Math::MPFR::Rmpfr_less_p($rterm, $rstop);
      Math::MPFR::Rmpfr_add($rsum, $rsum, $rterm, $rnd);
    }
    my $strval = Math::MPFR::Rmpfr_get_str($rsum, 10, $xdigits, $rnd);
    return ($wantbf)  ?  Math::BigFloat->new($strval)  :  0.0 + $strval;
  }

  if (defined $bignum::VERSION || ref($x) =~ /^Math::Big/) {
    require Math::Prime::Util::ZetaBigFloat;
    return Math::Prime::Util::ZetaBigFloat::RiemannR($x);
  }


  my $tol = 1e-16;
  my $sum = 0.0;
  my($y, $t);
  my $c = 0.0;

  $y = 1.0-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
  my $flogx = log($x);
  my $part_term = 1.0;
  for my $k (1 .. 10000) {
    # Small k from table, larger k from function
    my $zeta = ($k <= $#_Riemann_Zeta_Table)
               ? $_Riemann_Zeta_Table[$k+1-2]
               : RiemannZeta($k+1);
    $part_term *= $flogx / $k;
    my $term = $part_term / ($k + $k * $zeta);
    $y = $term-$c; $t = $sum+$y; $c = ($t-$sum)-$y; $sum = $t;
    last if $term < ($tol * $sum);
  }
  return $sum;
}

1;

__END__


# ABSTRACT: Pure Perl version of Math::Prime::Util

=pod

=encoding utf8


=head1 NAME

Math::Prime::Util::PP - Pure Perl version of Math::Prime::Util


=head1 VERSION

Version 0.14


=head1 SYNOPSIS

The functionality is basically identical to L<Math::Prime::Util>, as this
module is just the Pure Perl implementation.

  # Normally you would just import the functions you are using.
  # Nothing is exported by default.
  use Math::Prime::Util ':all';


  # Get a big array reference of many primes
  my $aref = primes( 100_000_000 );

  # All the primes between 5k and 10k inclusive
  my $aref = primes( 5_000, 10_000 );

  # If you want them in an array instead
  my @primes = @{primes( 500 )};


  # is_prime returns 0 for composite, 2 for prime
  say "$n is prime"  if is_prime($n);

  # is_prob_prime returns 0 for composite, 2 for prime, and 1 for maybe prime
  say "$n is ", qw(composite maybe_prime? prime)[is_prob_prime($n)];


  # step to the next prime (returns 0 if the next one is more than ~0)
  $n = next_prime($n);

  # step back (returns 0 if given input less than 2)
  $n = prev_prime($n);


  # Return Pi(n) -- the number of primes E<lt>= n.
  $primepi = prime_count( 1_000_000 );
  $primepi = prime_count( 10**14, 10**14+1000 );  # also does ranges

  # Quickly return an approximation to Pi(n)
  my $approx_number_of_primes = prime_count_approx( 10**17 );

  # Lower and upper bounds.  lower <= Pi(n) <= upper for all n
  die unless prime_count_lower($n) <= prime_count($n);
  die unless prime_count_upper($n) >= prime_count($n);


  # Return p_n, the nth prime
  say "The ten thousandth prime is ", nth_prime(10_000);

  # Return a quick approximation to the nth prime
  say "The one trillionth prime is ~ ", nth_prime_approx(10**12);

  # Lower and upper bounds.   lower <= nth_prime(n) <= upper for all n
  die unless nth_prime_lower($n) <= nth_prime($n);
  die unless nth_prime_upper($n) >= nth_prime($n);


  # Get the prime factors of a number
  @prime_factors = factor( $n );


  # Precalculate a sieve, possibly speeding up later work.
  prime_precalc( 1_000_000_000 );

  # Free any memory used by the module.
  prime_memfree;

  # Alternate way to free.  When this leaves scope, memory is freed.
  my $mf = Math::Prime::Util::MemFree->new;


  # Random primes
  my $small_prime = random_prime(1000);      # random prime <= limit
  my $rand_prime = random_prime(100, 10000); # random prime within a range
  my $rand_prime = random_ndigit_prime(6);   # random 6-digit prime


=head1 DESCRIPTION

Pure Perl implementations of prime number utilities that are normally
handled with XS or GMP.  Having the Perl implementations (1) provides examples,
(2) allows the functions to run even if XS isn't available, and (3) gives
big number support if L<Math::Prime::Util::GMP> isn't available.  This is a
subset of L<Math::Prime::Util>'s functionality.

All routines should work with native integers or multi-precision numbers.  To
enable big numbers, use bigint or bignum:

    use bigint;
    say prime_count_approx(1000000000000000000000000)'
    # says 18435599767347543283712

This is still experimental, and some functions will be very slow.  The
L<Math::Prime::Util::GMP> module has much faster versions of many of these
functions.  Alternately, L<Math::Pari> has a lot of these types of functions.


=head1 FUNCTIONS

=head2 is_prime

  print "$n is prime" if is_prime($n);

Returns 2 if the number is prime, 0 if not.  For numbers larger than C<2^64>
it will return 0 for composite and 1 for probably prime, using a strong BPSW
test.  Also note there are probabilistic prime testing functions available.


=head2 primes

Returns all the primes between the lower and upper limits (inclusive), with
a lower limit of C<2> if none is given.

An array reference is returned (with large lists this is much faster and uses
less memory than returning an array directly).

  my $aref1 = primes( 1_000_000 );
  my $aref2 = primes( 1_000_000_000_000, 1_000_000_001_000 );

  my @primes = @{ primes( 500 ) };

  print "$_\n" for (@{primes( 20, 100 )});

Sieving will be done if required.  The algorithm used will depend on the range
and whether a sieve result already exists.  Possibilities include trial
division (for ranges with only one expected prime), a Sieve of Eratosthenes
using wheel factorization, or a segmented sieve.


=head2 next_prime

  $n = next_prime($n);

Returns the next prime greater than the input number.  If the input is not a
bigint, then 0 is returned if the next prime is larger than a native integer
type (the last representable primes being C<4,294,967,291> in 32-bit Perl and
C<18,446,744,073,709,551,557> in 64-bit).


=head2 prev_prime

  $n = prev_prime($n);

Returns the prime smaller than the input number.  0 is returned if the
input is C<2> or lower.


=head2 prime_count

  my $primepi = prime_count( 1_000 );
  my $pirange = prime_count( 1_000, 10_000 );

Returns the Prime Count function C<Pi(n)>, also called C<primepi> in some
math packages.  When given two arguments, it returns the inclusive
count of primes between the ranges (e.g. C<(13,17)> returns 2, C<14,17>
and C<13,16> return 1, and C<14,16> returns 0).

The Lehmer method is used for large values, which speeds up results greatly.


=head2 nth_prime

  say "The ten thousandth prime is ", nth_prime(10_000);

Returns the prime that lies in index C<n> in the array of prime numbers.  Put
another way, this returns the smallest C<p> such that C<Pi(p) E<gt>= n>.

The Lehmer prime count is used to speed up results for large inputs, but both
methods take quite a bit of time and space.  Think abut whether a bound or
approximation would be acceptable instead.


=head2 is_strong_pseudoprime

=head2 miller_rabin

  my $maybe_prime = is_strong_pseudoprime($n, 2);
  my $probably_prime = is_strong_pseudoprime($n, 2, 3, 5, 7, 11, 13, 17);

Takes a positive number as input and one or more bases.  The bases must be
greater than 1.  Returns 2 is C<n> is definitely prime, 1 if C<n>
is probably prime, and 0 if C<n> is definitely composite.  Since this is
just the Miller-Rabin test, a value of 2 is only returned for inputs of
2 and 3, which are shortcut.  If 0 is returned, then the number really is a
composite.  If 1 is returned, there is a good chance the number is prime
(depending on the input and the bases), but we cannot be sure.

This is usually used in combination with other tests to make either stronger
tests (e.g. the strong BPSW test) or deterministic results for numbers less
than some verified limit (such as the C<is_prob_prime> function in this module).


=head2 is_strong_lucas_pseudoprime

Takes a positive number as input, and returns 1 if the input is a strong
Lucas pseudoprime using the Selfridge method of choosing D, P, and Q (some
sources call this a strong Lucas-Selfridge pseudoprime).  This is one half
of the BPSW primality test (the Miller-Rabin strong pseudoprime test with
base 2 being the other half).

=head2 is_aks_prime

Takes a positive number as input, and returns 1 if the input can be proven
prime using the AKS primality test.  This code is included for completeness
and as an example, but is impractically slow.


=head1 UTILITY FUNCTIONS

=head2 prime_precalc

  prime_precalc( 1_000_000_000 );

Let the module prepare for fast operation up to a specific number.  It is not
necessary to call this, but it gives you more control over when memory is
allocated and gives faster results for multiple calls in some cases.  In the
current implementation this will calculate a sieve for all numbers up to the
specified number.


=head2 prime_memfree

  prime_memfree;

Frees any extra memory the module may have allocated.  Like with
C<prime_precalc>, it is not necessary to call this, but if you're done
making calls, or want things cleanup up, you can use this.  The object method
might be a better choice for complicated uses.


=head1 FACTORING FUNCTIONS

=head2 factor

  my @factors = factor(3_369_738_766_071_892_021);
  # returns (204518747,16476429743)

Produces the prime factors of a positive number input, in numerical order.
The special cases of C<n = 0> and C<n = 1> will return C<n>, which
guarantees multiplying the factors together will always result in the
input value, though those are the only cases where the returned factors
are not prime.


=head2 trial_factor

  my @factors = trial_factor($n);

Produces the prime factors of a positive number input.  The factors will be
in numerical order.  The special cases of C<n = 0> and C<n = 1> will return
C<n>, while with all other inputs the factors are guaranteed to be prime.
For large inputs this will be very slow.

=head2 fermat_factor

  my @factors = fermat_factor($n);

Currently unimplementated in Perl.

=head2 holf_factor

  my @factors = holf_factor($n);

Produces factors, not necessarily prime, of the positive number input.  An
optional number of rounds can be given as a second parameter.  It is possible
the function will be unable to find a factor, in which case a single element,
the input, is returned.  This uses Hart's One Line Factorization with no
premultiplier.  It is an interesting alternative to Fermat's algorithm,
and there are some inputs it can rapidly factor.  In the long run it has the
same advantages and disadvantages as Fermat's method.

=head2 squfof_factor

  my @factors = squfof_factor($n);

Currently unimplementated in Perl.

=head2 prho_factor

=head2 pbrent_factor

=head2 pminus1_factor

  my @factors = prho_factor($n);

  # Use a very small number of rounds
  my @factors = prho_factor($n, 1000);

Produces factors, not necessarily prime, of the positive number input.  An
optional number of rounds can be given as a second parameter.  These attempt
to find a single factor using one of the probabilistic algorigthms of
Pollard Rho, Brent's modification of Pollard Rho, or Pollard's C<p - 1>.
These are more specialized algorithms usually used for pre-factoring very
large inputs, or checking very large inputs for naive mistakes.  If the
input is prime or they run out of rounds, they will return the single
input value.  On some inputs they will take a very long time, while on
others they succeed in a remarkably short time.



=head1 MATHEMATICAL FUNCTIONS

=head2 ExponentialIntegral

  my $Ei = ExponentialIntegral($x);

Given a non-zero floating point input C<x>, this returns the real-valued
exponential integral of C<x>, defined as the integral of C<e^t/t dt>
from C<-infinity> to C<x>.

If the bignum module has been loaded, all inputs will be treated as if they
were Math::BigFloat objects.

We first check to see if the Math::MPFR module is installed.  If so, then
it is used, as it will return results much faster and can be more accurate.
Accuracy when using MPFR will be 17 digits for non-BigInt/BigFloats, and
for BigInt/BigFloat inputs will be equal to the C<accuracy()> value of the
input (or the default BigFloat accuracy, which is 40 by default).

MPFR is used for positive inputs only.  If Math::MPFR is not installed or the
input is negative, then other methods are used:
continued fractions (C<x E<lt> -1>),
rational Chebyshev approximation (C< -1 E<lt> x E<lt> 0>),
a convergent series (small positive C<x>),
or an asymptotic divergent series (large positive C<x>).
Accuracy should be at least 14 digits.


=head2 LogarithmicIntegral

  my $li = LogarithmicIntegral($x)

Given a positive floating point input, returns the floating point logarithmic
integral of C<x>, defined as the integral of C<dt/ln t> from C<0> to C<x>.
If given a negative input, the function will croak.  The function returns
0 at C<x = 0>, and C<-infinity> at C<x = 1>.

This is often known as C<li(x)>.  A related function is the offset logarithmic
integral, sometimes known as C<Li(x)> which avoids the singularity at 1.  It
may be defined as C<Li(x) = li(x) - li(2)>.

We first check to see if the Math::MPFR module is installed.  If so, then
it is used, as it will return results much faster and can be more accurate.
Accuracy when using MPFR will be 17 digits for non-BigInt/BigFloats, and
for BigInt/BigFloat inputs will be equal to the C<accuracy()> value of the
input (or the default BigFloat accuracy, which is 40 by default).

MPFR is used for inputs greater than 1 only.  If Math::MPFR is not installed or
the input is less than 1, results will be calculated as C<Ei(ln x)>.

=head2 RiemannZeta

  my $z = RiemannZeta($s);

Given a floating point input C<s> where C<s E<gt>= 0.5>, returns the floating
point value of ζ(s)-1, where ζ(s) is the Riemann zeta function.  One is
subtracted to ensure maximum precision for large values of C<s>.  The zeta
function is the sum from k=1 to infinity of C<1 / k^s>

If the bignum module has been loaded, all inputs will be treated as if they
were Math::BigFloat objects.

We first check to see if the Math::MPFR module is installed.  If so, then
it is used, as it will return results much faster and can be more accurate.
Accuracy when using MPFR will be 17 digits for non-BigInt/BigFloats, and
for BigInt/BigFloat inputs will be equal to the C<accuracy()> value of the
input (or the default BigFloat accuracy, which is 40 by default).

If Math::MPFR is not installed, then results are calculated either from a
table, rational Chebyshev approximation, or via a series.


=head2 RiemannR

  my $r = RiemannR($x);

Given a positive non-zero floating point input, returns the floating
point value of Riemann's R function.  Riemann's R function gives a very close
approximation to the prime counting function.

If the bignum module has been loaded, all inputs will be treated as if they
were Math::BigFloat objects.

We first check to see if the Math::MPFR module is installed.  If so, then
it is used, as it will return results much faster and can be more accurate.
Accuracy when using MPFR will be 17 digits for non-BigInt/BigFloats, and
for BigInt/BigFloat inputs will be equal to the C<accuracy()> value of the
input (or the default BigFloat accuracy, which is 40 by default).


=head1 LIMITATIONS

The SQUFOF and Fermat factoring algorithms are not implemented yet.

Some of the prime methods use more memory than they should, as the segmented
sieve is not properly used in C<primes> and C<prime_count>.


=head1 PERFORMANCE

Performance compared to the XS/C code is quite poor for many operations.  Some
operations that are relatively close for small and medium-size values:

  next_prime / prev_prime
  is_prime / is_prob_prime
  miller_rabin
  ExponentialIntegral / LogarithmicIntegral / RiemannR
  primearray

Operations that are slower include:

  primes
  random_prime / random_ndigit_prime
  factor / all_factors
  nth_prime
  primecount

Performance improvement in this code is still possible.  The prime sieve is
over 2x faster than anything I was able to find online, but it is still has
room for improvement.

L<Math::Prime::Util::GMP> offers C<C+XS+GMP> support for most of the important
functions, and will be vastly faster for most operations.  If you install that
module, L<Math::Prime::Util> will load it automatically, meaning you should
not have to think about what code is actually being used (C, GMP, or Perl).

Memory use will generally be higher for the PP code, and in some cases B<much>
higher.  Some of this may be addressed in a later release.

For small values (e.g. primes and prime counts under 10M) most of this will
not matter.


=head1 SEE ALSO

L<Math::Prime::Util>

L<Math::Prime::Util::GMP>


=head1 AUTHORS

Dana Jacobsen E<lt>dana@acm.orgE<gt>


=head1 COPYRIGHT

Copyright 2012 by Dana Jacobsen E<lt>dana@acm.orgE<gt>

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
