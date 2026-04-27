use v5.28;
use feature 'signatures';

use Test2::V0 -no_srand => 1;
no warnings 'experimental::signatures';

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not available" unless value_tags_enabled;

# use same Scalar::ValueTags type for all tests
my $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);

# Check that value tags pass through other variables
{
    my $source = "value";
    add_value_tag( $vt_type, \$source, my $datum = [] );

    my $scalar_sink = $source;
    is( get_value_tags( $vt_type, \$scalar_sink ), [ exact_ref($datum) ],
        'value tags are preserved by scalar copy' );

    my @array_sink = ( $source );
    is( get_value_tags( $vt_type, \$array_sink[0] ), [ exact_ref($datum) ],
        'value tags are preseerved by array elements' );

    my %hash_sink = ( val => $source );
    is( get_value_tags( $vt_type, \$hash_sink{val} ), [ exact_ref($datum) ],
        'value tags are preseerved by hash elements' );
}

# Check that value tags pass through call/return
{
    my $source = "value";
    add_value_tag( $vt_type, \$source, my $datum = [] );

    sub func_via_snail {
        is( get_value_tags( $vt_type, \$_[0] ), [ exact_ref($datum) ],
            'value tags are preserved by @_ on call' );
    }
    func_via_snail( $source );

    sub func_via_shift {
        is( get_value_tags( $vt_type, \shift ), [ exact_ref($datum) ],
            'value tags are preserved by shift @_ on call' );
    }
    func_via_shift( $source );

    sub func_via_signature ( $x ) {
        is( get_value_tags( $vt_type, \$x ), [ exact_ref($datum) ],
            'value tags are preserved by signatured param on call' );
    }
    func_via_signature( $source );

    sub func_return {
        return $source;
    }
    is( get_value_tags( $vt_type, \func_return() ), [ exact_ref($datum) ],
        'value tags are preserved by function return' );
}

# Now we know basic containers and call/return works, we can use those to more
# efficiently test a bunch of other ops

sub code_value_tags_ok ( $code, $name )
{
    my $inp = "1";
    add_value_tag( $vt_type, \$inp, my $dat = { datum => "here" } );

    my $out = $code->( $inp );
    is( get_value_tags( $vt_type, \$out ), [ exact_ref($dat) ],
        "$name preserves value tags" );
}

# array ops
code_value_tags_ok( sub ($x) { my @arr; push @arr, $x; $arr[0] }, 'push' );
code_value_tags_ok( sub ($x) { my @arr; unshift @arr, $x; $arr[0] }, 'unshift' );
code_value_tags_ok( sub ($x) { my @arr = ( $x ); shift @arr }, 'shift' );
code_value_tags_ok( sub ($x) { my @arr = ( $x ); pop @arr }, 'pop' );
code_value_tags_ok( sub ($x) { my @arr; splice @arr, 0, 0, ( $x ); $arr[0] }, 'splice in' );
code_value_tags_ok( sub ($x) { my @arr = ( $x ); splice @arr, 0, 1 }, 'splice out' );

# hash ops
code_value_tags_ok( sub ($x) { my %hash = ( key => $x ); ( values %hash )[0] }, 'values' );
# keys aren't SVs so can't have value tags
code_value_tags_ok( sub ($x) { my %hash = ( key => $x ); delete $hash{key} }, 'delete' );

# other control flow
code_value_tags_ok( sub ($x) { my $ret = do { $x; }; $ret }, 'do BLOCK' );
code_value_tags_ok( sub ($x) { my $ret = eval { $x; }; $ret }, 'eval BLOCK' );

done_testing;
