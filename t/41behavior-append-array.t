use v5.28;

use Test2::V0;

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not enabled" unless value_tags_enabled;

# use same ScalarValueTags type for all tests
my $vt_type;
{
    $vt_type = register_value_tags_type(SVTAGS_APPEND_ARRAY);
    ok( $vt_type, 'register_value_tags_type');
}

# combining one tagged variable with one untagged variable
{
    my $var_one = 123;
    my $tag = { tag => 'one' };
    add_value_tag( $vt_type, \$var_one, $tag );

    my $var_two = 456;

    my $in_order = $var_one + $var_two;

    is( get_value_tags( $vt_type, \$in_order ), [$tag],
        'get_value_tags should return initial tag when tag is on first variable' );

    my $out_of_order = $var_two + $var_one;
    is( get_value_tags( $vt_type, \$out_of_order ), [$tag],
        'get_value_tags should return initial tag when tag is on second variable' );
}

# combining two tagged variables
{
    my $var_one = 123;
    my $tag_one = { tag => 'one' };
    say STDERR "NCM DEBUG: add tag on var_one";
    add_value_tag( $vt_type, \$var_one, $tag_one );

    is( get_value_tags( $vt_type, \$var_one ), [$tag_one],
        'get_value_tags on first variable should be correct' );

    my $var_two = 456;
    my $tag_two = { tag => 'two' };
    say STDERR "NCM DEBUG: add tag on var_two";
    add_value_tag( $vt_type, \$var_two, $tag_two );

    is( get_value_tags( $vt_type, \$var_two ), [$tag_two],
        'get_value_tags on second variable should be correct' );

    say STDERR "NCM DEBUG: combine var_one and var_two";
    my $combined = $var_one + $var_two;
    say STDERR "NCM DEBUG: done combining var_one and var_two";

    # FIXME: is tag order deterministic in implementation?
    is( get_value_tags( $vt_type, \$combined ), [ $tag_one, $tag_two ],
        'get_value_tags should return both tags' );
}

# combining duplicate tags
{
    my $tag_one = { tag => 'one' };
    my $tag_two = { tag => 'two' };

    my $var = 123;
    add_value_tag( $vt_type, \$var, $tag_one );

    is( get_value_tags( $vt_type, \$var ), [ $tag_one ],
        'after first tag_one added, get_value_tags should return tag_one' );

    add_value_tag( $vt_type, \$var, $tag_one );

    is( get_value_tags( $vt_type, \$var ), [ $tag_one, $tag_one ],
        'after second tag_one added, get_value_tags should return two copies of tag_one' );

    add_value_tag( $vt_type, \$var, $tag_two );

    # FIXME: is tag order deterministic in implementation?
    is( get_value_tags( $vt_type, \$var ), [ $tag_one, $tag_one, $tag_two ],
        'after first tag_two added, get_value_tags should return two copies of tag_one and one tag_two' );

    add_value_tag( $vt_type, \$var, $tag_two );

    is( get_value_tags( $vt_type, \$var ), [ $tag_one, $tag_one, $tag_two, $tag_two ],
        'after second tag_two added, get_value_tags should return two copies of tag_one and two of tag_two' );
}

done_testing;
1;
