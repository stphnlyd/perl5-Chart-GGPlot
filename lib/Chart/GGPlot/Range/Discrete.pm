package Chart::GGPlot::Range::Discrete;

# ABSTRACT: Discrete range

use Chart::GGPlot::Class qw(:pdl);
use namespace::autoclean;

# VERSION

with qw(Chart::GGPlot::Range);

sub _build_range { PDL::SV->new([]); }

use List::AllUtils qw(uniq);
use Types::PDL -types;

use Chart::GGPlot::Util qw(:all);

# See R scales package train_descrete() method
method train($p, $drop = false, $na_rm = false ) {
    return $self->range if $p->isempty;

    unless (is_discrete($p)) {
        die "Continuous value supplied to discrete scale";
    }
    
    my @range = @{ $self->range->unpdl };
    if ( $p->$_DOES('PDL::Factor') ) {
        # TODO: This may be incorrect.
        push @range, $p->levels->flatten;
        $self->range( ref($p)->new( [ uniq(@range) ] ) );
    }
    else {
        push @range, $p->flatten;
        $self->range( ref($p)->new( [ sort(uniq(@range)) ] ) );
    }

    return $self->range;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SEE ALSO

L<Chart::GGPlot::Range>

