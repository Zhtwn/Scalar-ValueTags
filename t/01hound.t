use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Data::Hounding;
skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED;

# probe constant
{
    ok( IS_HOUNDING_ENABLED, 'IS_HOUNDING_ENABLED constant is true' );
}

# query on empty var yields nothing
{
    my $var = 123;
    is( [ hound_query( \$var ) ], [],
        'hound_query on empty variable' );

    is( [ hound_query( \do{ 12 + 34 } ) ], [],
        'hound_query on empty intermediate expression' );
}

# apply + query on a variable
{
    my $var = 456;
    is( scalar hound_query( \$var ), undef,
        'hound_query returns undef on an un-hounded variable in scalar context' );

    hound_apply( \$var, my $datum = { data => "one" } );

    is( [ hound_query( \$var ) ], [ exact_ref($datum) ],
        'hound_query on variable yields previously-set datum' );

    hound_apply( \$var, $datum );
    is( [ hound_query( \$var ) ], [ exact_ref($datum) ],
        'hound_apply is idempotent on the same datum' );
    is( scalar hound_query( \$var ), 1,
        'hound_query counts one annotation in scalar context' );

    hound_apply( \$var, { data => "two" } );
    is( [ hound_query( \$var ) ],
        # TODO: Maybe order doesn't matter? Is this just an unordered set?
        [ exact_ref($datum), { data => "two" } ],
        'hound_query yields two annotations' );
    is( scalar hound_query( \$var ), 2,
        'hound_query counts two annotations in scalar context' );

    hound_delete( \$var );
    is( [ hound_query( \$var ) ], [],
        'hound_delete removes annotation' );
}

# undef on a variable removes the annotation
{
    my $var = 789;
    hound_apply( \$var, { } );

    undef $var;
    is( [ hound_query( \$var ) ], [],
        'hound_query is empty after undef' );
}

# overwriting an existing variable removes the annotation
{
    my $var = 789;
    hound_apply( \$var, { } );

    $var = "";
    is( [ hound_query( \$var ) ], [],
        'hound_query is empty after overwritten contents' );
}

# undef in a variable itself can still be hounded
{
    my $var;
    hound_apply( \$var, { } );

    is( [ hound_query( \$var ) ], [ { } ],
        'hound_query on a variable even if undef' );
}

# duplicate annotation references are filtered
{
    my $var;
    hound_apply( \$var, my $datum = \"annotation" );
    hound_apply( \$var, $datum );
    hound_apply( \$var, $datum );

    is( [ hound_query( \$var ) ], [ exact_ref($datum) ],
        'hound_apply filters duplicat refs' );
}

done_testing;
