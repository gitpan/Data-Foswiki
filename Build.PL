use 5.006;
use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
    class => 'My::Builder',

    code => <<'END_CODE',

sub ACTION_authortest {
    my ($self) = @_;

    $self->depends_on('build');
    $self->depends_on('manifest');
    $self->depends_on('distmeta');

    $self->test_files( qw< t xt > );
    $self->recursive_test_files(1);

    $self->depends_on('test');

    return;
}

sub ACTION_distdir {
    my ($self) = @_;

    $self->depends_on('authortest');

    return $self->SUPER::ACTION_distdir();
}

END_CODE
);

my $builder = $class->new(
    module_name       => 'Data::Foswiki',
    license           => 'perl',
    create_license    => 1,
    dist_author       => q{Sven Dowideit <SvenDowideit@fosiki.com>},
    dist_version_from => 'lib/Data/Foswiki.pm',
    abstract_from     => 'lib/Data/Foswiki.pm',
    create_readme     => 1,
    build_requires    => {
        'Test::More' => 0,

    },

    #    #mmm, does not exist?
    #    build_recommends => {
    #'Test::CheckManifest' => '0.9',
    #'Test::Pod'           => 0,
    #'Test::Pod::Coverage' => 0,
    #'Pod::Coverage'       => 0,
    #'Test::Spelling'      => 0,
    #'Test::Kwalitee'      => 0,
    #},
    configure_requires => { 'Module::Build' => 0.38 },
    requires           => { 'perl'          => 5.006, },
    add_to_cleanup     => [ 'Data-Foswiki-*', 't/*~', 't/*.bak' ],
    create_makefile_pl => 'small',
    meta_add           => {
        resources => {
            homepage   => 'http://sourceforge.net/projects/module-build',
            repository => 'git://github.com/SvenDowideit/Data-Foswiki.git',

            #            x_twitter => 'http://twitter.com/SvenDowideit/',
        }
    }
);

$builder->create_build_script();
