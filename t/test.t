#!/usr/bin/perl
use strict;
use warnings;

use Test::More tests => 13;
use Data::Dumper;

use_ok( 'Class::Entangle' );

is( $Class::Entangle::VERSION, 0.06, "Testing against correct version" );

#{{{ Test::TestClass
{
    package Test::TestClass::Parent;
    use strict;
    use warnings;

    sub parent_method {
        my $self = shift;
        return $self;
    }

    our $parent_scalar = "parent";
}
{
    package Test::TestClass;
    use strict;
    use warnings;

    use base 'Test::TestClass::Parent';

    sub new {
        my $class = shift;
        $class = ref $class || $class;

        return bless {}, $class;
    }

    sub subA {
        return "subA";
    }

    sub subB($) {
        my $self = shift;
        my ( $in ) = @_;
        return "subB($in)";
    }

    sub subD;

    my $local = "local";
    our $scalarA = "scalar";
    our $scalarB = "scalar";
    our %hashA = ( 'hash' => 'hash' );
    our @arrayB = ( 'array' );

    open( FH, "<", "/dev/null" ) || die( "Could not open null: $!\n" );

    # If anyone seriously did a package variable filehandle and expected people
    # to use it directly, they should be shot. Here for completeness.
    open( our $scalarFH, "<", "/dev/null" ) || die( "Could not open null: $!\n" );

    END {
        close( FH );
        close( $scalarFH );
    }

}
#}}}
#{{{ Test::TestTieScalar
{
    package Test::TestTieScalar;
    require Tie::Scalar;
    our @ISA = qw(Tie::Scalar);

    sub TIESCALAR {
        my $class = shift;
        my ( $varname ) = @_;
        bless( { varname => $varname }, $class );
    }

    sub FETCH {
        my $self = shift;
        my $varname = $self->{ varname };

        no strict 'refs';
        return ${ "Test\::TestClass\::$varname" };
    }

    sub STORE {
        my $self = shift;
        my $varname = $self->{ varname };
        my ( $value ) = @_;

        no strict 'refs';
        return ${ "Test\::TestClass\::$varname" } = $value;
    }
}
#}}}

my $test = Test::TestClass->new;
my $entanglement = entanglement( $test );

#{{{ Test the entanglement hash
for ( values %$entanglement ) {
    $_ = [ sort @$_ ] if ref $_ eq 'ARRAY';
}
is_deeply(
    $entanglement,
    {
        CODE    => [ sort qw/ subA subB new parent_method /],
        SCALAR  => [ sort qw/ scalarB scalarA scalarFH parent_scalar VERSION /],
        HASH    => [ 'hashA' ],
        ARRAY   => [ 'ISA', 'arrayB' ],
        IO      => [ sort qw/ FH /],
        class   => ref $test,
    },
    "Definition is complete and correct list of subs and variables",
);
#}}}

#{{{ Test simple syntax for just a sub entanglement
my $entangler = entangler(
    $entanglement,
    sub {
        my $entangle = shift;
        my $subname = shift;
        if ( $entangle ) {
            return $entangle->{ entangled }->$subname( @_ );
        }
        else {
            return &{ "Test\::TestClass\::$subname" }->( @_ );
        }
    }
);

my $entangle = entangle(
    $entangler,
    entangled => $test,
);

is_deeply(
    $entangle->$_( 'a' ),
    $test->$_( 'a' ),
    "Return from both test and entangle objects match for $_('a')"
) for ( @{ $entanglement->{ CODE }});
#}}}

#{{{ Test complex syntax with tied scalars
$entangler = entangler(
    $entanglement,
    CODE => sub {
        my $entangle = shift;
        my $subname = shift;
        if ( $entangle ) {
            return $entangle->{ entangled }->$subname( @_ );
        }
        else {
            return &{ "Test\::TestClass\::$subname" }->( @_ );
        }
    },
    SCALAR => 'Test::TestTieScalar',
    variation => 'WithScalars',
);

$entangle = entangle(
    $entangler,
    entangled => $test,
);

is_deeply(
    $entangle->$_( 'a' ),
    $test->$_( 'a' ),
    "Return from both test and entangle objects match for $_('a')"
) for ( @{ $entanglement->{ CODE }});

is( $Test::TestClass::scalarA, 'scalar', "Scalar is set." );

{
    no strict 'refs';
    my $entangleclass = ref $entangle;
    is( ${"$entangleclass\::scalarA"}, $Test::TestClass::scalarA, "Scalar match" );
}
#}}}

