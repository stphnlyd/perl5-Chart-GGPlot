package Chart::GGPlot::Geom::Rect;

# ABSTRACT: Class for rect geom

use Chart::GGPlot::Class;
use MooseX::Singleton;

# VERSION

use Chart::GGPlot::Aes;
use Chart::GGPlot::Util qw(pt stroke);

with qw(Chart::GGPlot::Geom);

has '+non_missing_aes' => ( default => sub { [qw(size shape colour)] } );
has '+default_aes'     => (
    default => sub {
        Chart::GGPlot::Aes->new(
            color    => NA(),
            fill     => PDL::SV->new(["grey35"]),
            size     => pdl(0.5),
            linetype => PDL::SV->new(["solid"]),
            alpha    => NA(),
        );
    }
);

classmethod required_aes() { [qw(xmin xmax ymin ymax)] };

__PACKAGE__->meta->make_immutable;

1;

__END__