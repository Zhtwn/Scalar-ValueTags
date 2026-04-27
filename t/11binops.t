use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not available" unless value_tags_enabled;

# use same Scalar::ValueTags type for all tests
my $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);

sub binop_value_tags_ok ( $code, $result, $name )
{
    my $inp = "1";
    add_value_tag( $vt_type, \$inp, my $dat = { datum => "here" } );

    {
        my $out = $code->( $inp, 1 );
        is( get_value_tags( $vt_type, \$out ), [ exact_ref($dat) ],
            "$name preserves LHS value_tags on output" );
        is( $out, $result, "$name yields correct result" );
    }

    {
        my $out = $code->( 1, $inp );
        is( get_value_tags( $vt_type, \$out ), [ exact_ref($dat) ],
            "$name preserves RHS value_tags on output" );
        is( $out, $result, "$name yields correct result" );
    }

    my $second_inp = "1";
    add_value_tag( $vt_type, \$second_inp, my $second_dat = { datum => "second" } );
    {
        my $second_out = $code->( $second_inp, 1 );
        is( get_value_tags( $vt_type, \$second_out ), [ exact_ref($second_dat) ],
            "$name a second time does not leak on LHS" );
    }
    {
        my $second_out = $code->( 1, $second_inp );
        is( get_value_tags( $vt_type, \$second_out ), [ exact_ref($second_dat) ],
            "$name a second time does not leak on RHS" );
    }
}

binop_value_tags_ok( sub ($x, $y) { $x +  $y },      2, "add" );
binop_value_tags_ok( sub ($x, $y) { $x += $y; $x },  2, "add mutating" );
binop_value_tags_ok( sub ($x, $y) { $x -  $y },      0, "subtract" );
binop_value_tags_ok( sub ($x, $y) { $x -= $y; $x },  0, "subtract mutating" );
binop_value_tags_ok( sub ($x, $y) { $x *  $y },      1, "multiply" );
binop_value_tags_ok( sub ($x, $y) { $x *= $y; $x },  1, "multiply mutating" );
binop_value_tags_ok( sub ($x, $y) { $x /  $y },      1, "divide" );
binop_value_tags_ok( sub ($x, $y) { $x /= $y; $x },  1, "divide mutating" );
binop_value_tags_ok( sub ($x, $y) { $x %  $y },      0, "modulo" );
binop_value_tags_ok( sub ($x, $y) { $x %= $y; $x },  0, "modulo mutating" );
binop_value_tags_ok( sub ($x, $y) { $x **  $y },     1, "power" );
binop_value_tags_ok( sub ($x, $y) { $x **= $y; $x }, 1, "power mutating" );
binop_value_tags_ok( sub ($x, $y) { $x <<  $y },     2, "left-shift" );
binop_value_tags_ok( sub ($x, $y) { $x <<= $y; $x }, 2, "left-shift mutating" );
binop_value_tags_ok( sub ($x, $y) { $x >>  $y },     0, "right-shift" );
binop_value_tags_ok( sub ($x, $y) { $x >>= $y; $x }, 0, "right-shift mutating" );

binop_value_tags_ok( sub ($x, $y) { $x &  $y },     1, "bitwise-and" );
binop_value_tags_ok( sub ($x, $y) { $x &= $y; $x }, 1, "bitwise-and mutating" );
binop_value_tags_ok( sub ($x, $y) { $x |  $y },     1, "bitwise-or" );
binop_value_tags_ok( sub ($x, $y) { $x |= $y; $x }, 1, "bitwise-or mutating" );
binop_value_tags_ok( sub ($x, $y) { $x ^  $y },     0, "bitwise-xor" );
binop_value_tags_ok( sub ($x, $y) { $x ^= $y; $x }, 0, "bitwise-xor mutating" );

binop_value_tags_ok( sub ($x, $y) { $x .  $y },     "11", "concat" );
binop_value_tags_ok( sub ($x, $y) { $x .= $y; $x }, "11", "concat mutating" );

done_testing;
