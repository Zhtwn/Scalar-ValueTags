use v5.28;
no warnings 'experimental::signatures';
use feature 'signatures';

use Test2::V0;

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not available" unless value_tags_enabled;

# use same Scalar::ValueTags type for all tests
my $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);

sub value_tags_ok ( $code, $result, $name )
{
    my $inp = "1";
    add_value_tag( $vt_type, \$inp, my $dat = { datum => "here" } );

    my $out = $code->( $inp );
    is( get_value_tags( $vt_type, \$out ), [ exact_ref($dat) ],
        "$name preserves value tags on output" );
    is( $out, $result, "$name yields correct result" );
}

# custom inline function
sub inline_sum0 ( @x ) {
    my $total = 0;
    $total += $_ for @x;
    return $total;
}

value_tags_ok( sub ( $x ) { inline_sum0( $x, 2, 3 ) }, 6, 'inline sum0' );

BEGIN {
    require List::Util::PP;
    *pp_sum0 = \&List::Util::PP::sum0;
}

value_tags_ok( sub ( $x ) { pp_sum0( $x, 2, 3 ) }, 6, 'sum0 from List::Util::PP' );

BEGIN {
    require List::Util;
    *xs_sum0 = \&List::Util::sum0;
}

value_tags_ok( sub ( $x ) { xs_sum0( $x, 2, 3 ) }, 6, 'sum0 from List::Util' );

done_testing;
