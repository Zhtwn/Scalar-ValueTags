package Scalar::ValueTags 0.001;

use v5.28;

require XSLoader;
XSLoader::load( __PACKAGE__, our $VERSION );

use Exporter 'import';
our @EXPORT = qw( hound_apply hound_query hound_delete IS_HOUNDING_ENABLED IS_HOUNDING_TRACING_ENABLED );

# Test if the module is actually working
{
    hound_apply( \my $var1, \123 );
    my $var2 = $var1; # this only copies the hounding if perl core supports it

    # Export a constant to say if this works
    *IS_HOUNDING_ENABLED = scalar(hound_query( \$var2 )) ? sub () { !!1 } : sub () { !!0 };
    *IS_HOUNDING_TRACING_ENABLED = scalar(hound_tracing_enabled()) ? sub () { !!1 } : sub () { !!0 };
}

1;

=head1 NAME

C<Scalar::ValueTags> - Infectious magic data invisibly attached to variables

=head1 SYNOPSIS

FIXME - rewrite once new API is shaped
    use Scalar::ValueTags;

    # apply hounding annotation to $foo
    my $annotation = 'origin: somewhere';
    my $foo        = 32;
    hound_apply( \$foo, \$annotation );

    my @annotations = hound_query( \$foo );
    # returns ['origin: somewhere']

    # annotations are propagated along with value
    my $bar = $foo + 9;

    my @annotations = hound_query( \$bar );
    # returns ['origin: somewhere']

    # delete all hounding annotations
    hound_delete( \$foo ):

=head1 DESCRIPTION

FIXME - rewrite once new API is shaped

The C<Scalar::ValueTags> module provides functions for managing hounding
annotations to variables.

A "hounding annotation" is a metadata string describing the value of
a variable. The initial use case is to generate real-time data lineage
records that indicate all of the input sources used to derive an output
value.

Every time a value is assigned to a variable, all of the hounding
annotations from all input variables are copied to the derived variable.
This allows tracing the lineage of all data within a system by applying
hounding when data is received from an external source, and reporting
the hounding annotations when data is sent to an external destination.

The hounding annotations are handled as a logical set: annotations are
de-duplicated as they are added to a variable's hounding. Thus, the
hounding annotations are unordered.

This module exports the C<hound_apply>, C<hound_query>, and
C<hound_delete> functions, as well as the C<IS_HOUNDING_ENABLED>
constant.

The propagation of the annotations is done by using the Value Magic
feature that is being added to core Perl as part of Magic V2. By using
Value Magic's C<infect> callback, C<Scalar::ValueTags> combines all of
the unique hounding annotations from all of the source variables, and
attaches them to the destination variable.

This module is similar to L<Variable::Magic>, but with some key
differences. Notably, while most magic applies to variables and remains
with a variable regardless of what value it currently stores, the
annotations applied by this module are associated with the value itself,
regardless of what variable currently stores it.

=over 4

=item * Value magic is copied on assignment

When values are copied through the assignment operator, or implictly by
operations such as storing and retriving values in arrays and hashes, or
passing or returning values to subroutines.

    my $foo = $hounded_variable;
    # $foo now has the same hounding annotations

    func($hounded_variable);
    sub func($x) {
        # $x will be similarly annotated
    }

=item * Value magic is combined through calculations

If you have one or more values with hounding data in an expression, the result
will have the combined hounding data of all the hounded variables.

    # $foo will have combined hounding data from $hounded_variable and
    # $hounded_variable2
    my $foo = $hounded_variable + $x + $hounded_variable2;

=item * Value magic is lost when values are overwritten

When a new value is written into a variable currently containing a hounded
value, if that new value does not have any hounding annotations then the
variable no longer appears to contain such annotations.

    my $foo = $hounded_value;
    $foo = "a program constant";

    # $foo no longer has any hounding annotations

=back

=head1 FUNCTIONS

=head2 hound_apply

    my $var = 42;
    hound_apply( \$var, [ 123 ] );
    print $var; # 42
    my @result = hound_query( \$var );
    print @result; # ARRAY(0x...)

The C<hound_apply> function invisibly applies hounding data to a variable via
magic. The first argument is a reference to the variable, and the second
argument is the hounding data. Hounding data must be references; non-reference
scalars are not permitted.

Subsequent calls to C<hound_apply> on the same variable will append the
hounding data to the variable.

At the present time, hounding may be applied to scalar, array, and hash
references.

=head2 hound_query

    my @result = hound_query( \$var );

    my $count = hound_query( \$var );

The C<hound_query> function queries the hounding data of a variable. The
argument is a reference to the variable. It returns the hounding data of the
variable.

In scalar context, it returns the number of hounding data items attached to
the data, or C<undef> if the variable is not hounded.

=head2 hound_delete

    hound_delete( \$var );

The C<hound_delete> function deletes the hounding behavior on the data.

=head2 IS_HOUNDING_ENABLED

    if ( IS_HOUNDING_ENABLED ) {
        say "Hounding is enabled!";
    }

This constant is automatically exported into your namespace. It is true if the
module is able to apply and query hounding data, and false otherwise.

=head1 BEHAVIOR

This module grew out of a client's need for L<data
lineage|https://en.wikipedia.org/wiki/Data_lineage> tracking, but it can be
used for many other cases. It allows you to invisibly attach data to other
data without changing any code. This can be useful for debugging, logging, or
similar things. Note that the behavior of the variable is not changed! Also,
if you apply a reference as the hounding data (the second argument to
C<hound_apply>), the reference is I<not> applied if the same reference as the
previous reference.

    my $var = 42;
    hound_apply( \$var1, 123 );
    say $var; # 42
    my @result = hound_query( \$var );
    say @result; # 123
    hound_apply( \$var, { foo => 456 } );
    @result = hound_query( \$var );
    say @result; # 123, { foo => 456 }

    hound_apply( \$var, { foo => 456 } );
    @result = hound_query( \$var );
    say @result; # 123, { foo => 456 }

=head1 CORE IMPLEMENTATIONS

=head2 USERTAINT

Originally, C<Scalar::ValueTags> was developed on top of the C<USERTAINT> core
patches, which leveraged the Perl C<taint> behavior to add and propagate
hounding annotations on variables. This was a proof-of-concept core
implementation that provided the needed behavior in an I<ad hoc> manner.
The C<USERTAINT> implementation includes quite a bit of workaround
code that handles special cases that could not be done directly with
C<taint>. Some of these workarounds needed to be implemented in
C<Scalar::ValueTags> so that the Perl operator overloads would happen
at the correct time.

=head2 Hooks / Magic v2

In 2025, the Perl core implementation of C<Magic v2> was developed. which
extends Perl's C<magic> with a number of new features. One of the features
is C<Value Magic>, which provides a much simpler way to propagate hounding
annotations. With C<Magic v2>, all of the propagation logic is done and
tested in the Perl core.

=head2 Transition

Currently, C<Scalar::ValueTags> detects whether the C<Magic v2> or
C<USERTAINT> implementation is available in Perl core, and uses that.

This allows the same C<Scalar::ValueTags> code to be used for testing
C<Bookings::Data::Lineage> code on a C<USERTANT>-patched Perl 5.36.0.
When the C<Magic v2> feature is merged into a future version of Perl
and Booking is using that Perl version, then C<Scalar::ValueTags> and
all of the C<Bookings::Data::Lineage> code will continue to behave
in the same manner (modulo any bugs in the POC C<USERTAINT> code).

To ensure that C<Scalar::ValueTags> works the same on both C<USERTAINT>
and C<Magic v2>, the differences between implementations have been
isolated into four low-level functions: C<get_hounding_magic>,
C<add_hounding_magic>, C<remove_hounding_magic>, and C<get_hounding_av>.
Other than the additional Perl operator overrides specific to C<USERTAINT>,
the rest of the C<Scalar::ValueTags> code is shared between the two core
implementations.

=head1 DEBUGGING

=head2 Devel::MAT::Dumper

If C<Devel::MAT::Dumper> is installed, then C<Scalar::ValueTags> will add any
hounding annotations to the dumped data.

See C<HAVE_DMD_HELPER> in the XS code.

=head2 DEBUG_TRACE_ANNOTATIONS

If C<Scalar::ValueTags> is configured with the C<--with-trace> option, then
additional Perl magic is added to each of the hounding annotations indicating
the source code origin of that annotation.

To enable this, use C<perl Build.PL --with-trace>.

=head2 USERTAINT debugging

Any of the Perl operations that are overridden by C<Scalar::ValueTags> when
using the C<USERTAINT> application can be disabled by setting an environment
variable. This is primarily useful for debugging the portion of C<USERTAINT>
implemented in C<Scalar::ValueTags>, and is not likely to be very helpful
otherwise.

To disable these Perl operation overrides, set a C<PERL_DATA_HOUNDING_DISABLE>
environment variable to a comma-separated list of any of the flag names listed
below. Each included flag will disable the Perl operation overriding for that
specific operation.

The flag names are:

=over 4

=item B<match>

The special code around C<m/.../> regexp match operations that is responsible
for setting up the C<$1>, C<$2> etc variables.

=item B<subst>

The special code around C<s/.../.../> regexp substitution operations that sets
up C<$1> etc and also handles hounded expressions in the replacement.

=back

For example:

    $ PERL_DATA_HOUNDING_DISABLE=match perl -MScalar::ValueTags ...
