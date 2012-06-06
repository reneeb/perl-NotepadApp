package NotepadApp::Utils;

use strict;
use warnings;

use Data::UUID;
use DBI;
use Digest::SHA;
use File::Basename;
use File::Path qw(mkpath);
use File::Spec;
use Git::Repository;
use HTML::FromANSI::Tiny;

use parent 'Exporter';

our @EXPORT = qw(
    check_authentication
    create_notepad
    get_content
    get_diff
    get_history
    get_meta
    is_authenticated
    save_notepad
);

my $dir = File::Spec->rel2abs(
    File::Spec->catdir(
        dirname( __FILE__ ),
        '..',
        '..',
    ),
);

my $db       = File::Spec->catfile( $dir, 'notepad.db' );
my $dbh      = DBI->connect( 'DBI:SQLite:' . $db );
my $uuid_obj = Data::UUID->new;
my $git_dir  = File::Spec->rel2abs(
    File::Spec->catdir( $dir, '..','NotepadDocs' ),
);
my $git      = Git::Repository->new( work_tree => $git_dir );


sub check_authentication {
    my $app = shift;

    my $ip        = $app->tx->remote_address;
    my $id        = $app->stash->{id};
    my $time      = time;
    my $user_pass = $app->param( 'notepad_passwd' );

    my $passwd = _notepad_requires_login( $id );
    return 1 if !$passwd;

    my $pass_check = Digest::SHA->new( 256 )->add( $user_pass )->hexdigest;
    return 0 if $pass_check ne $passwd;

    my $session_id = $uuid_obj->create_str;
    my $insert_sql = 'INSERT INTO sessions (notepad_id, session_id, start, ip) VALUES (?,?,?,?)';
    my $insert_sth = $dbh->prepare( $insert_sql );

    $insert_sth->execute( $id, $session_id, $time, $ip );

    $app->session(
        notepad_id => $id,
        session_id => $session_id,
    );

    return 1;
}

sub create_notepad {
    my $app = shift;

    my $title   = $app->param( 'title' );
    my $passwd  = $app->param( 'notepad_passwd' );
    my $comment = $app->param( 'comment' );
    my $owner   = $app->param( 'owner' );
    my $uuid    = $uuid_obj->create_str;

    if ( $passwd ) {
        $passwd = Digest::SHA->new( '256' )->add( $passwd )->hexdigest;
    }
    
    my $notepad_path = _get_notepad_path( $uuid );

    open my $fh, '>', $notepad_path;
    close $fh;

    chdir $git_dir;

    $notepad_path =~ s/ \A \Q$git_dir\E \///x;
    
    my $add_output    = Git::Repository->run( add => $notepad_path );
    my $commit_output = Git::Repository->run( 
        commit => 
        '-m'       => 'created notepad', 
        '--author' => ( $owner || 'tester' ) . ' <notepad@perl-services.de>', 
        $notepad_path
    );

    my ($id) = $commit_output =~ m! \[ master \s+ ([a-zA-Z0-9]+) \] !x;

    my $insert_sql = 'INSERT INTO articles (id, uuid, notepad_passwd, comment, title ) VALUES (?,?,?,?,?)';
    my $insert_sth = $dbh->prepare( $insert_sql ) or die $dbh->errstr;
    $insert_sth->execute( $id, $uuid, $passwd, $comment, $title );

    return $id;
}

sub get_content {
    my $id = shift;

    my $uuid    = _get_uuid_by_id( $id );
    my $notepad = _get_notepad_path( $uuid );

    my $content = '';
    if ( $uuid and -f $notepad and open my $fh, '<', $notepad ) {
        local $/;
        $content = <$fh>;
    }

    return $content;
}

sub get_diff {
    my $id     = shift;
    my $commit = shift;
    my $opts   = shift;

    my $uuid    = _get_uuid_by_id( $id );
    my $notepad = _get_notepad_path( $uuid );

    $notepad =~ s/ \A \Q$git_dir\E \///x;

    my @opts;

    my $want_html;
    if ( $opts and $opts->{format} and lc $opts->{format} eq 'html' ) {
        push @opts, '--color-words';
        $want_html = 1;
    }

    my $diff    = $git->run(
        diff =>
        @opts,
        $commit . '^',
        $commit,
        $notepad,
    );

    $diff =~ s/\Q$notepad\E/$id/gs;

    my $diff_text;

    if ( $want_html ) {
        my $htmler = HTML::FromANSI::Tiny->new( background => 'white', foreground => 'black' );
        $diff_text = $htmler->style_tag . $htmler->html( $diff );
    }
    else {
        $diff_text = $diff;
    }

    return $diff_text;
}

sub get_history {
    my $id = shift;

    my $uuid    = _get_uuid_by_id( $id );
    my $notepad = _get_notepad_path( $uuid );
    $notepad    =~ s/ \A \Q$git_dir\E \///x;
    my $output  = $git->run( log => '-z', $notepad );

    my @commits = split /\0/, $output;

    my @history;
    for my $commit ( @commits ) {
        my ($commit,$author,$date) = $commit =~ m!
            commit \s+ ([a-zA-Z0-9]{8}) [a-zA-Z0-9]+ \n
            Author: \s+ (.*?) \s+ <.*?> \n
            Date: \s+ (.*?) \n
        !x;

        my ($wday,$month,$day,$time,$year) = split/\s+/, $date;

        $time =~ s/:\d+\z//;

        my $date_formatted = sprintf "%s %s, %s (%s)", $month, $day, $year, $time;

        push @history, { hash => $commit, author => $author, date => $date_formatted };
    }

    return \@history;
}

sub get_meta {
    my $id = shift;

    my $select_sql = 'SELECT * FROM articles WHERE id = ? LIMIT 1';
    my $select_sth = $dbh->prepare( $select_sql );
    $select_sth->execute( $id );

    my $articles  = $select_sth->fetchall_arrayref({}) || [{}];
    my ($article) = @{ $articles };

    return %{$article};
}

sub is_authenticated {
    my $app = shift;

    my $session_id = $app->session( 'session_id' );
    my $notepad_id = $app->session( 'notepad_id' );

    my $nid_from_route = $app->url_for;
    $nid_from_route =~ s![^a-zA-Z0-9]!!g;

    return 1 if !_notepad_requires_login( $nid_from_route );

    my $ip = $app->tx->remote_address;

    my $select_sql = 'SELECT * FROM sessions WHERE session_id = ? AND notepad_id = ?';
    my $select_sth = $dbh->prepare( $select_sql );
    $select_sth->execute( $session_id, $notepad_id );

    my $session = $select_sth->fetchrow_hashref;
    return if !$session;

    my $time = time;
    if ( 
        $time - $session->{start} > 3600
        or $ip ne $session->{ip}
    ) {
        return;
    }

    my $update_sql = 'UPDATE sessions SET start = ?';
    my $update_sth = $dbh->prepare( $update_sql );
    $update_sth->execute( $time );

    return 1;
}

sub save_notepad {
    my $app = shift;

    my $author  = $app->param( 'author' );
    my $comment = $app->param( 'commit_message' );
    my $text    = $app->param( 'body' );
    my $id      = $app->stash->{id};

    my $uuid    = _get_uuid_by_id( $id );
    
    my $notepad_path = _get_notepad_path( $uuid );

    open my $fh, '>', $notepad_path;
    print $fh $text;
    close $fh;

    chdir $git_dir;

    $notepad_path =~ s/ \A \Q$git_dir\E \///x;
    my $commit_output = Git::Repository->run( 
        commit => 
        '-m'       => $comment || '<no message>', 
        '--author' => ( $author || 'anonymous' ) . ' <notepad@perl-services.de>',
        $notepad_path,
    );
}

sub _clean_sessions {
}

sub _get_uuid_by_id {
    my $id = shift;

    my $select_sql = 'SELECT uuid FROM articles WHERE id = ? LIMIT 1';
    my $select_sth = $dbh->prepare( $select_sql );
    $select_sth->execute( $id );

    my ($uuid) = $select_sth->fetchrow_array;
    return $uuid;
}

sub _get_notepad_path {
    my $uuid = shift;

    my @parts = split /-/, $uuid;
    pop @parts;

    my $dir = File::Spec->catdir( $git_dir, @parts );
    if ( !-d $dir ) {
        mkpath $dir;
    }

    my $path = File::Spec->catfile(
        $git_dir,
        @parts,
        $uuid,
    );

    return $path;
}

sub _notepad_requires_login {
    my $id = shift;

    my $select_sql = 'SELECT notepad_passwd FROM articles WHERE id = ?';
    my $select_sth = $dbh->prepare( $select_sql );

    $select_sth->execute( $id );

    my ($passwd) = $select_sth->fetchrow_array;

    return $passwd;
}

1;
