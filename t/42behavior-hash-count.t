use v5.28;

use Test2::V0;

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not enabled" unless value_tags_enabled;

# use same ScalarValueTags type for all tests
my $vt_type;
{
    $vt_type = register_value_tags_type(SVTAGS_HASH_COUNT);
    ok( $vt_type, 'register_value_tags_type');
}

# combining one tagged variable with one untagged variable
{
    my $var_one = 123;
    say STDERR "TEST: var_one: " . \$var_one;
    my $tag = 'test_tag';
    say STDERR "TEST: tag: '$tag'";
    add_value_tag( $vt_type, \$var_one, $tag );

    is( get_value_tags( $vt_type, \$var_one ), {$tag => 1},
        'get_value_tags should return tags from tagged variable' );

    my $var_two = 456;

    is( get_value_tags( $vt_type, \$var_two ), undef,
        'get_value_tags should return undef from untagged variable' );

    say STDERR "TEST: var_two: " . \$var_two;

    say STDERR "TEST: combine var_one and var_two";
    my $in_order = $var_one + $var_two;

    is( get_value_tags( $vt_type, \$in_order ), {$tag => 1},
        'get_value_tags should return initial tag when tag is on first variable' );

    say STDERR "TEST: combine var_two and var_one";
    my $out_of_order = $var_two + $var_one;
    is( get_value_tags( $vt_type, \$out_of_order ), {$tag => 1},
        'get_value_tags should return initial tag when tag is on second variable' );
}

# combining two tagged variables
{
    my $var_one = 123;
    my $tag_one = 'tag_one';
    say STDERR "TEST: add tag on var_one: '$tag_one'";
    add_value_tag( $vt_type, \$var_one, $tag_one );

    is( get_value_tags( $vt_type, \$var_one ), {$tag_one => 1},
        'get_value_tags on first variable should be correct' );

    my $var_two = 456;
    my $tag_two = 'tag_two';
    say STDERR "TEST: add tag on var_two: '$tag_two'";
    add_value_tag( $vt_type, \$var_two, $tag_two );

    is( get_value_tags( $vt_type, \$var_two ), {$tag_two => 1},
        'get_value_tags on second variable should be correct' );

    say STDERR "TEST: combine var_one and var_two";
    my $combined = $var_one + $var_two;
    say STDERR "TEST: done combining var_one and var_two";

    is( get_value_tags( $vt_type, \$combined ), {$tag_one => 1, $tag_two => 1},
        'get_value_tags should return both tags' );
}

# combining duplicate tags
{
    my $tag_one = 'tag_one';
    my $tag_two = 'tag_two';

    my $var = 123;
    add_value_tag( $vt_type, \$var, $tag_one );

    is( get_value_tags( $vt_type, \$var ), {$tag_one => 1},
        'after first tag_one added, get_value_tags should return one count of tag_one' );

    add_value_tag( $vt_type, \$var, $tag_one );

    is( get_value_tags( $vt_type, \$var ), {$tag_one => 2},
        'after second tag_one added, get_value_tags should return two counts of tag_one' );

    add_value_tag( $vt_type, \$var, $tag_two );

    # FIXME: is tag order deterministic in implementation?
    is( get_value_tags( $vt_type, \$var ), { $tag_one => 2, $tag_two => 1 },
        'after first tag_two added, get_value_tags should return two counts of tag_one and one of tag_two' );

    add_value_tag( $vt_type, \$var, $tag_two );

    is( get_value_tags( $vt_type, \$var ), { $tag_one => 2, $tag_two => 2 },
        'after second tag_two added, get_value_tags should return two counts of both tag_one and tag_two' );
}

done_testing;
1;
