use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Data::Hounding;
skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED;

sub binop_hounded_ok ( $code, $result, $name )
{
    my $inp = "1";
    hound_apply( \$inp, my $dat = { datum => "here" } );

    {
        my $out = $code->( $inp, 1 );
        is( [ hound_query( \$out ) ], [ exact_ref($dat) ],
            "$name preserves LHS hounding on output" );
        is( $out, $result, "$name yields correct result" );
    }

    {
        my $out = $code->( 1, $inp );
        is( [ hound_query( \$out ) ], [ exact_ref($dat) ],
            "$name preserves RHS hounding on output" );
        is( $out, $result, "$name yields correct result" );
    }

    my $second_inp = "1";
    hound_apply( \$second_inp, my $second_dat = { datum => "second" } );
    {
        my $second_out = $code->( $second_inp, 1 );
        is( [ hound_query( \$second_out ) ], [ exact_ref($second_dat) ],
            "$name a second time does not leak on LHS" );
    }
    {
        my $second_out = $code->( 1, $second_inp );
        is( [ hound_query( \$second_out ) ], [ exact_ref($second_dat) ],
            "$name a second time does not leak on RHS" );
    }
}

binop_hounded_ok( sub ($x, $y) { $x +  $y },      2, "add" );
binop_hounded_ok( sub ($x, $y) { $x += $y; $x },  2, "add mutating" );
binop_hounded_ok( sub ($x, $y) { $x -  $y },      0, "subtract" );
binop_hounded_ok( sub ($x, $y) { $x -= $y; $x },  0, "subtract mutating" );
binop_hounded_ok( sub ($x, $y) { $x *  $y },      1, "multiply" );
binop_hounded_ok( sub ($x, $y) { $x *= $y; $x },  1, "multiply mutating" );
binop_hounded_ok( sub ($x, $y) { $x /  $y },      1, "divide" );
binop_hounded_ok( sub ($x, $y) { $x /= $y; $x },  1, "divide mutating" );
binop_hounded_ok( sub ($x, $y) { $x %  $y },      0, "modulo" );
binop_hounded_ok( sub ($x, $y) { $x %= $y; $x },  0, "modulo mutating" );
binop_hounded_ok( sub ($x, $y) { $x **  $y },     1, "power" );
binop_hounded_ok( sub ($x, $y) { $x **= $y; $x }, 1, "power mutating" );
binop_hounded_ok( sub ($x, $y) { $x <<  $y },     2, "left-shift" );
binop_hounded_ok( sub ($x, $y) { $x <<= $y; $x }, 2, "left-shift mutating" );
binop_hounded_ok( sub ($x, $y) { $x >>  $y },     0, "right-shift" );
binop_hounded_ok( sub ($x, $y) { $x >>= $y; $x }, 0, "right-shift mutating" );

binop_hounded_ok( sub ($x, $y) { $x &  $y },     1, "bitwise-and" );
binop_hounded_ok( sub ($x, $y) { $x &= $y; $x }, 1, "bitwise-and mutating" );
binop_hounded_ok( sub ($x, $y) { $x |  $y },     1, "bitwise-or" );
binop_hounded_ok( sub ($x, $y) { $x |= $y; $x }, 1, "bitwise-or mutating" );
binop_hounded_ok( sub ($x, $y) { $x ^  $y },     0, "bitwise-xor" );
binop_hounded_ok( sub ($x, $y) { $x ^= $y; $x }, 0, "bitwise-xor mutating" );

binop_hounded_ok( sub ($x, $y) { $x .  $y },     "11", "concat" );
binop_hounded_ok( sub ($x, $y) { $x .= $y; $x }, "11", "concat mutating" );

done_testing;
