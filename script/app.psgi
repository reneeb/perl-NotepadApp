#!/usr/bin/perl

use strict;
use warnings;

use File::Basename;
use File::Spec;
use Mojolicious::Lite;
use Text::Markdown qw(markdown);

my $dir;
BEGIN {
    $dir = File::Spec->rel2abs( dirname __FILE__ );
}

use lib File::Spec->catdir( $dir, '..', 'lib' );

use NotepadApp::Utils;


push @{ app->renderer->paths }, File::Spec->catdir( $dir, '..', 'templates' );
push @{ app->static->paths }, File::Spec->catdir( $dir, '..', 'public' );


get '/' => sub { shift->render( 'index' ); };

post '/' => sub {
    my ($self) = shift;

    my $id = create_notepad( $self ) || '';
    return $self->redirect_to( '/' . $id . '/edit' );
};

post '/:id/login' => sub {
    my $self = shift;

    my $is_authorized = check_authentication( $self );

    my $mode = $is_authorized ? '' : 'login';

    my $id  = $self->stash->{id};
    my $url = sprintf "/%s/%s", $id, $mode;

    return $self->redirect_to( $url );
};

get '/:id/login' => sub {
    my $self = shift;

    $self->render( 'login' );
};

under sub {
    my $self = shift;

    return 1 if is_authenticated( $self );

    my $id = $self->url_for;
    $id =~ s/[^a-zA-Z0-9]//g;

    $self->stash( id => $id );
    $self->render( 'login' );
    return;
};

get '/:id' => sub {
    my $self = shift;

    my $id       = $self->param( 'id' );
    my $content  = get_content( $id );
    my %metadata = get_meta( $id );
    my $history  = get_history( $id );

    $self->stash(
        %metadata,
        history => $history,
        body    => markdown( $content ),
    );
    $self->render( 'show' );
};

get '/:id/edit' => sub {
    my $self = shift;

    my $id       = $self->param( 'id' );
    my $content  = get_content( $id );
    my %metadata = get_meta( $id );

    $self->stash( %metadata, body => $content );
    $self->render( 'edit' );
};

post '/:id/save' => sub {
    my $self = shift;

    my $id = $self->param( 'id' );
    save_notepad( $self );
    return $self->redirect_to( '/' . $id );
};

get '/:id/changes/:commit' => sub {
    my $self = shift;

    my $id      = $self->stash->{id};
    my $commit  = $self->stash->{commit};
    my $diff    = get_diff( $id, $commit, { format => 'html' } );

    $self->stash( diff => $diff, id => $id );
    $self->render( 'diff' );
};

app->start;
