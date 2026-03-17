use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Data::Hounding;
skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED;

# Check that hounding passes through other variables
{
    my $source = "value";
    hound_apply( \$source, my $datum = [] );

    my $scalar_sink = $source;
    is( [ hound_query( \$scalar_sink ) ], [ exact_ref($datum) ],
        'hounding is preserved by scalar copy' );

    my @array_sink = ( $source );
    is( [ hound_query( \$array_sink[0] ) ], [ exact_ref($datum) ],
        'hounding is preseerved by array elements' );

    my %hash_sink = ( val => $source );
    is( [ hound_query( \$hash_sink{val} ) ], [ exact_ref($datum) ],
        'hounding is preseerved by hash elements' );
}

# Check that hounding passes through call/return
{
    my $source = "value";
    hound_apply( \$source, my $datum = [] );

    sub func_via_snail {
        is( [ hound_query( \$_[0] ) ], [ exact_ref($datum) ],
            'hounding is preserved by @_ on call' );
    }
    func_via_snail( $source );

    sub func_via_shift {
        is( [ hound_query( \shift ) ], [ exact_ref($datum) ],
            'hounding is preserved by shift @_ on call' );
    }
    func_via_shift( $source );

    sub func_via_signature ( $x ) {
        is( [ hound_query( \$x ) ], [ exact_ref($datum) ],
            'hounding is preserved by signatured param on call' );
    }
    func_via_signature( $source );

    sub func_return {
        return $source;
    }
    is( [ hound_query( \func_return() ) ], [ exact_ref($datum) ],
        'hounding is preserved by function return' );
}

# Now we know basic containers and call/return works, we can use those to more
# efficiently test a bunch of other ops

sub code_hounded_ok ( $code, $name )
{
    my $inp = "1";
    hound_apply( \$inp, my $dat = { datum => "here" } );

    my $out = $code->( $inp );
    is( [ hound_query( \$out ) ], [ exact_ref($dat) ],
        "$name preserves hounding" );
}

# array ops
code_hounded_ok( sub ($x) { my @arr; push @arr, $x; $arr[0] }, 'push' );
code_hounded_ok( sub ($x) { my @arr; unshift @arr, $x; $arr[0] }, 'unshift' );
code_hounded_ok( sub ($x) { my @arr = ( $x ); shift @arr }, 'shift' );
code_hounded_ok( sub ($x) { my @arr = ( $x ); pop @arr }, 'pop' );
code_hounded_ok( sub ($x) { my @arr; splice @arr, 0, 0, ( $x ); $arr[0] }, 'splice in' );
code_hounded_ok( sub ($x) { my @arr = ( $x ); splice @arr, 0, 1 }, 'splice out' );

# hash ops
code_hounded_ok( sub ($x) { my %hash = ( key => $x ); ( values %hash )[0] }, 'values' );
# keys aren't SVs so can't be hounded
code_hounded_ok( sub ($x) { my %hash = ( key => $x ); delete $hash{key} }, 'delete' );

# other control flow
code_hounded_ok( sub ($x) { my $ret = do { $x; }; $ret }, 'do BLOCK' );
code_hounded_ok( sub ($x) { my $ret = eval { $x; }; $ret }, 'eval BLOCK' );

done_testing;
