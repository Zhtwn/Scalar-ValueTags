use v5.28;
no warnings 'experimental::signatures';
use feature 'signatures';

use Test2::V0;

use Data::Hounding;
BEGIN { skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED; }

sub hounded_ok ( $code, $result, $name )
{
    my $inp = "1";
    hound_apply( \$inp, my $dat = { datum => "here" } );

    my $out = $code->( $inp );
    is( [ hound_query( \$out ) ], [ exact_ref($dat) ],
        "$name preserves hounding on output" );
    is( $out, $result, "$name yields correct result" );
}

# custom inline function
sub inline_sum0 ( @x ) {
    my $total = 0;
    $total += $_ for @x;
    return $total;
}

hounded_ok( sub ( $x ) { inline_sum0( $x, 2, 3 ) }, 6, 'inline sum0' );

BEGIN {
    require List::Util::PP;
    *pp_sum0 = \&List::Util::PP::sum0;
}

hounded_ok( sub ( $x ) { pp_sum0( $x, 2, 3 ) }, 6, 'sum0 from List::Util::PP' );

BEGIN {
    require List::Util;
    *xs_sum0 = \&List::Util::sum0;
}

hounded_ok( sub ( $x ) { xs_sum0( $x, 2, 3 ) }, 6, 'sum0 from List::Util' );

done_testing;
