use v5.28;
use feature 'signatures';

use Test2::V0 -no_srand => 1;
no warnings 'experimental::signatures';

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not available" unless value_tags_enabled;

# use same Scalar::ValueTags type for all tests
my $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);

sub unop_value_tags_ok ( $code, $result, $name )
{
    my $inp = "1";
    add_value_tag( $vt_type, \$inp, my $dat = { datum => "here" } );

    my $out = $code->( $inp );
    is( get_value_tags( $vt_type, \$out ), [ exact_ref($dat) ],
        "$name preserves value tags on output" );
    is( $out, $result, "$name yields correct result" );

    my $second_inp = "1";
    add_value_tag( $vt_type, \$second_inp, my $second_dat = { datum => "second" } );

    my $second_out = $code->( $second_inp );
    is( get_value_tags( $vt_type, \$second_out ), [ exact_ref($second_dat) ],
        "$name a second time does not leak" );
}

unop_value_tags_ok( sub ($x) { -$x }, -1, "negate" );
unop_value_tags_ok( sub ($x) { ~$x }, ~1, "complement" );

# Check that inplace edits preserve the value tags of their mutated variable
unop_value_tags_ok( sub ($x) { chop $x; $x }, "", "chop" );
unop_value_tags_ok( sub ($x) { chomp $x; $x }, "1", "chomp" );

unop_value_tags_ok( sub ($x) { length $x }, 1, "length" );

sub mut_unop_value_tags_ok ( $code, $result, $newvar, $name )
{
    my $inp = "1";
    add_value_tag( $vt_type, \$inp, my $dat = { datum => "here" } );

    my ( $out, $outvar ) = $code->( $inp );
    is( get_value_tags( $vt_type, \$out ), [ $dat ],
        "$name preserves value tags on output" );
    is( $out, $result, "$name yields correct result" );
    is( get_value_tags( $vt_type, \$outvar ), [ $dat ],
        "$name preserves value tags on mutated variable" );
    is( $outvar, $newvar, "$name correctly mutates variable" );

    my $second_inp = "1";
    add_value_tag( $vt_type, \$second_inp, my $second_dat = { datum => "second" } );

    my ( $second_out, $second_outvar ) = $code->( $second_inp );
    is( get_value_tags( $vt_type, \$second_out ), [ exact_ref($second_dat) ],
        "$name a second time does not leak on output" );
    is( get_value_tags( $vt_type, \$second_outvar ), [ exact_ref($second_dat) ],
        "$name a second time does not leak on mutated variable" );
}

mut_unop_value_tags_ok( sub ($x) { ++$x, $x }, 2, 2, "preinc" );
mut_unop_value_tags_ok( sub ($x) { --$x, $x }, 0, 0, "predec" );
mut_unop_value_tags_ok( sub ($x) { $x++, $x }, 1, 2, "postinc" );
mut_unop_value_tags_ok( sub ($x) { $x--, $x }, 1, 0, "postdec" );

sub base_or_unop_value_tags_ok ( $code, $result, $name, $in_value = "1" )
{
    my $inp = $in_value;
    add_value_tag( $vt_type, \$inp, my $dat = { datum => "here" } );

    my ( $outbase, $outun ) = $code->( local $_ = $inp );
    is( get_value_tags( $vt_type, \$outbase ), [ $dat ],
        "$name as BASEOP preserves value tags on output" );
    is( $outbase, $result, "$name as BASEOP yields correct result" );
    is( get_value_tags( $vt_type, \$outun ), [ $dat ],
        "$name as UNOP preserves value tags on output" );
    is( $outun, $result, "$name as UNOP yields correct result" );

    my $second_inp = $in_value;
    add_value_tag( $vt_type, \$second_inp, my $second_dat = { datum => "second" } );

    my ( $second_outbase, $second_outun ) = $code->( local $_ = $second_inp );
    is( get_value_tags( $vt_type, \$second_outbase ), [ exact_ref($second_dat) ],
        "$name as BASEOP a second time does not leak on output" );
    is( get_value_tags( $vt_type, \$second_outun ), [ exact_ref($second_dat) ],
        "$name as UNOP a second time does not leak on output" );
}

use feature 'fc';

base_or_unop_value_tags_ok( sub ($x) { uc, uc $_ }, "XYZ", "uc", "xyz" );
base_or_unop_value_tags_ok( sub ($x) { ucfirst, ucfirst $_ }, "Xyz", "ucfirst", "xyz" );
base_or_unop_value_tags_ok( sub ($x) { lc, lc $_ }, "xyz", "lc", "XYZ" );
base_or_unop_value_tags_ok( sub ($x) { lcfirst, lcfirst $_ }, "xYZ", "lcfirst", "XYZ" );
base_or_unop_value_tags_ok( sub ($x) { fc, fc $_ }, fc "xYz", "fc", "xYz" );
base_or_unop_value_tags_ok( sub ($x) { ord, ord $_ }, ord 1, "ord" );
base_or_unop_value_tags_ok( sub ($x) { chr, chr $_ }, chr 1, "chr" );

done_testing;
