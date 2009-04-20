#{{{ POD

=pod

=head1 NAME

Class::Entangle - Functions to entangle an object.

=head1 DESCRIPTION

Class::Entangle is names after Quantum Entanglement, which is where 2
partacles are entangled in such a way that events occuring to one occur to the
other as well, even if they are seperated by great distance.

Using Class::Entangle you can pull an 'entanglement' from a class. This
entanglement contains a list of class properties, which includes subroutines,
variables, and handles. This entanglement can be used to create entanglers,
which in turn can be used to entangle a class.

An entangler is a new class definition that contains definitions for subroutines,
variables, and handles that match another classes. When you define an entangler
you tell it how you want it to entangle each type. Subroutines are defined by
providing a callback routine. Variables and handers are defined using tie.

Once you have an entangler for a class you can use that class as you would your
original class. If the class is an object defenition then you can use the
entangle() function to create an instance of the entangler against an existing
object.

Note: You probably don't want to use construction methods through the entangler
class, it will return whatever the constructor for the original class returns.
This will return a new instance of the original class.

=head1 SYNOPSIS

    #!/usr/bin/perl
    use strict;
    use warnings;

    use Class::Entangle;

    # First define a class to entangle, as well as a Tie::Scalar class for
    # handling the scalars.
    {
        package MyClass;
        use strict;
        use warnings;

        sub new {
            my $class = shift;
            $class = ref $class if ref $class;
            return bless {}, $class;
        }

        sub subA {
            my $self = shift;
            my ( $in ) = @_;
            return "subA($in)";
        }

        our $scalarA = "scalar";
    }

    {
        package MyClass::TieScalar;
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
            return ${ "MyClass\::$varname" };
        }

        sub STORE {
            my $self = shift;
            my $varname = $self->{ varname };
            my ( $value ) = @_;

            no strict 'refs';
            return ${ "MyClass\::$varname" } = $value;
        }
    }

    my $one = MyClass->new;
    my $entanglement = Class::Entangle::entanglement( $one );
    # $entangler will contain the class name of the entangler.
    my $entangler = Class::Entangle::entangler(
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
        SCALAR => 'MyClass::TieScalar',
    );
    $entangle = Class::Entangle::entangle(
        $entangler,
        entangled => $test,
    );

    # prints: 'subA(a)'
    print $entangle->subA( 'a' );

    # prints: 'HaHa, I am messing with $MyClass::scalarA!'
    no strict 'refs';
    ${ "$entangler\::scalarA" } = 'HaHa, I am messing with MyClass::scalarA';
    print ${ "$entangler\::scalarA" }

=head1 EXPORTED FUNCTIONS

=over 4

=cut

#}}}
package Class::Entangle;
use strict;
use warnings;

use Exporter 'import';

our @EXPORT = qw/ entanglement entangler entangle /;
our $VERSION = '0.06';

my %DEFINED = (
    code => {},
    loaded => {},
    used => {},
);

=item entanglement( $object )

Only argument is the object to create an entanglement for. Returns an
entanglement.

Note: Currently entanglements are simple hashes, this is subject to change,
always get the entanglement returned by this function and use it directly, do
not write code that treats it directly as a hash.

=cut

sub entanglement {
    my ( $object ) = @_;
    my $class = ref $object || $object;

    unless ( $DEFINED{ $class }) {
        my %defs;

        no strict 'refs';
        for my $item ( $class, @{ "$class\::ISA" }) {
            my %set = _class_properties( $item );
            while ( my ( $prop, $value ) = each %set ) {
                $defs{ $prop } = { %{ $defs{ $prop } || {}}, %$value };
            }
        }

        for my $key ( keys %defs ) {
            $defs{ $key } = [ keys %{ $defs{ $key } }];
        }

        $DEFINED{ $class } = { class => $class, %defs };
    }

    return $DEFINED{ $class };
}

sub _class_properties {
    my ( $class ) = @_;
    no strict 'refs';

    my %defs;
    while( my ( $name, $ref ) = each %{ $class . "::" }) {
        next if $name =~ m/::$/;
        next if grep { $_ eq $name } (qw/BEGIN END/);

        $defs{ CODE }->{ $name }++   if defined &{$ref};
        $defs{ HASH }->{ $name }++   if defined %{$ref};
        $defs{ ARRAY }->{ $name }++  if defined @{$ref};
        $defs{ SCALAR }->{ $name }++ if defined ${$ref};

        # IO have no sigil to use, have to dig into the glob.
        $defs{ IO }->{ $name }++ if defined *{$ref}{IO};
    }

    return %defs;
}

=item entangler( $entanglement, %params )

The first arguement should be an entanglement as returned by entanglement().
All additional params should be key => value pairs. All the following are acceptible:

=over 4

variation => 'default' - When you create an entangler it creates a class
definition. This defenition contains the variation name you pass in here. If
you don't pass in a variation 'default' is used. You can only define an
entangler class against an entanglement once for each variation. If you want to
have a different entangler for the same object you must provide a variation
name.

CODE => sub { ... } - Define the subroutine callback to use on all class
subroutines. The first 2 parameters should always be shifted off before passing
@_ to the entangled class. The first is either the entagle object if the sub
was called as an object method, the entangler class if it was called as a class
method, or undef if not called as a method. The second parameter is always the
name of the sub that was called.

HASH, ARRAY, SCALAR, IO => 'Tie::MyTie' - Specify the class to tie the specific
variable type to. If you are writing a Tie for a specific variable you should
know that the call to Tie looks like this:

    # $ref is "$entangler\::$item"
    # $tieclass is the class you passed to 'HASH =>'
    # $item is the name of the variable.
    tie( %$ref, $tieclass, $item );

=back 4

=cut

sub entangler {
    my $entanglement = shift;
    my %params = (@_ > 1 ) ? @_ : ( CODE => shift( @_ ));

    my $class = $entanglement->{ class };
    my $variation = delete( $params{ variation } ) || 'default';

    my $defined = $DEFINED{ loaded }->{ $class }->{ $variation };

    warn(
        "Attempt to redefine '$class' variation '$variation'\n",
        "You can only define a variation once, if you are using a\n",
        "different subroutine callback, or different variable tie\n",
        "classes, then things will not behave as you expect.\n",
    ) if ( $defined and keys %params );

    _define_entangler( $entanglement, $variation, %params ) unless ( $defined );

    return $DEFINED{ loaded }->{ $class }->{ $variation };
}

sub _define_entangler {
    my ( $entanglement, $variation, %params ) = @_;
    my $class = $entanglement->{ class };
    my $entangleclass = ( delete $params{ entangleclass } ) ||
                        "Class\::_Entangle\::$class\::$variation";

    warn(
        "Warning, redefining entangleclass: $entangleclass\n",
        "This is almost certainly not what you want.\n"
    ) if $DEFINED{ used }->{ $entangleclass };

    $DEFINED{ used }->{ $entangleclass }++;

    no strict 'refs';

    # Take care of the subs
    if( my $ref = delete $params{ 'CODE' }) {
        for my $sub ( @{ $entanglement->{ 'CODE' }}) {
            *{ $entangleclass . '::' . $sub } = sub {
                my $first = $_[0];
                $first = ref $first || $first;
                my $self = shift if $first eq $entangleclass;
                $ref->( $self || undef, $sub, @_ );
            }
        }
    }

    # Take care of the variables and handles
    while ( my ( $type, $tieclass ) = each %params ) {
        for my $item ( @{ $entanglement->{ $type }}) {
            my $ref = $entangleclass . '::' . $item;
            tie( %$ref, $tieclass, $item ) if $type eq 'HASH';
            tie( @$ref, $tieclass, $item ) if $type eq 'ARRAY';
            tie( $$ref, $tieclass, $item ) if $type eq 'SCALAR';
            tie( *{ $ref }, $tieclass, $item ) if $type eq 'IO';
        }
    }

   $DEFINED{ loaded }->{ $class }->{ $variation } = $entangleclass;
}

=item entangle( $entangler, %object_params )

First param should be an entangler class as returned by entangler().

All additional parameters will be directly put into the hashref that is blessed
as an object of type $entangler.

=cut

sub entangle {
    my $entangler = shift;
    return bless( { @_ },  $entangler );
}

1;

#{{{ End Pod

__END__

=back

=head1 RESOURCES

=over 4

=item http://github.com/exodist/class-entangle/tree/master

=item git://github.com/exodist/class-entangle.git

=head1 AUTHOR

Chad Granum E<lt>exodist7@gmail.comE<gt>

=head1 COPYRIGHT

Copyright 2009 Chad Granum

licensed under the GPL version 3.
You should have received a copy of the GNU General Public License
along with this.  If not, see <http://www.gnu.org/licenses/>.

=cut

#}}}
