use v5.28;

use Test2::V0;

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not enabled" unless value_tags_enabled;

# probe constant
{
    ok( value_tags_enabled, 'value_tags_enabled constant is true' );
}

{
    ok( defined SVTAGS_UNIQUE_REF_ARRAY, 'SVTAGS_UNIQUE_REF_ARRAY should be defined' );
    ok( defined SVTAGS_APPEND_ARRAY, 'SVTAGS_APPEND_ARRAY should be defined' );
    ok( defined SVTAGS_HASH_COUNT, 'SVTAGS_HASH_COUNT should be defined' );
}

# use same ScalarValueTags type for all tests
my $vt_type;
{
    $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);
    ok( $vt_type, 'register_value_tags_type');
}

# var and expression without value tags
{
    my $var = 123;
    is( get_value_tags( $vt_type, \$var ), undef,
        'get_value_tags on untagged variable should return undef' );

    is( get_value_tags( $vt_type, \do{ 12 + 34 } ), undef,
        'get_value_tags on empty intermediate expression should return undef' );
}

# set and delete value tags on variable
{
    my $var = 456;
    is( get_value_tags( $vt_type, \$var ), undef,
        'get_value_tags on untagged variable should return undef' );

    my $tag_one = { data => 'one' };
    add_value_tag( $vt_type, \$var, $tag_one );

    # return value is specific to SVTAGS_UNIQUE_REF_ARRAY behavior
    is( get_value_tags( $vt_type, \$var ), [ exact_ref($tag_one) ],
        'get_value_tags on tagged variable should return tag reference' );

    # subsequent retrieval
    is( get_value_tags( $vt_type, \$var ), [ exact_ref($tag_one) ],
        'get_value_tags on tagged variable should return tag reference' );

    clear_value_tags( $vt_type, \$var );
    is( get_value_tags( $vt_type, \$var ), undef,
        'after clear_value_tags, get_value_tags on variable should return undef' );
}

# undefining a variable
{
    my $var = 789;
    add_value_tag( $vt_type, \$var, { } );

    undef $var;
    is( get_value_tags( $vt_type, \$var ), undef,
        'after undefining variable, get_value_tags should return undef' );
}

# overwriting a tagged variable
{
    my $var = 789;
    add_value_tag( $vt_type, \$var, { } );

    $var = "";
    is( get_value_tags( $vt_type, \$var ), undef,
        'after overwriting variable value, get_value_tags should return undef' );
}

# variable with undef value
{
    my $var;
    my $tag = { data => 9 };
    add_value_tag( $vt_type, \$var, $tag );

    is( get_value_tags( $vt_type, \$var ), [ exact_ref($tag) ],
        'on tagged variable with undef value, get_value_tags should return tag' );
}

done_testing;
1;
