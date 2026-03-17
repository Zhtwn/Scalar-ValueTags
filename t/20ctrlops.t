use v5.28;
use feature 'signatures';
use Feature::Compat::Try;

use Test2::V0;
no warnings 'experimental::signatures';

use Data::Hounding;
skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED;

sub hounded_ok ( $code, $result, $name )
{
    my $inp = "1";
    hound_apply( \$inp, my $dat = { datum => "here" } );

    my $out = $code->( $inp );
    is( [ hound_query( \$out ) ], [ exact_ref($dat) ],
        "$name preserves hounding on output" );
    is( $out, $result, "$name yields correct result" );

    my $second_inp = "1";
    hound_apply( \$second_inp, my $second_dat = { datum => "second" } );
    my $second_out = $code->( $second_inp );
    is( [ hound_query( \$second_out ) ], [ exact_ref($second_dat) ],
        "$name a second time does not leak on output" );
}

hounded_ok( sub ($x) {
    my $e = eval { die "Value is $x\n"; 1 } ? undef : $@;
    return $e;
}, "Value is 1\n", 'eval{} + $@' );

hounded_ok( sub ($x) {
    try { die "Value is $x\n"; }
    catch($e) { return $e };
    return undef;
}, "Value is 1\n", 'try/catch' );

done_testing;
