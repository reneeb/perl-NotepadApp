package NotepadApp::Utils;

use strict;
use warnings;

use Data::UUID;
use DBI;
use File::Spec;
use File::Basename;
use Git::Repository;

use parent 'Exporter';

our @EXPORT = qw(
    check_authentification
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
warn $dir;
my $git_dir  = File::Spec->rel2abs(
    File::Spec->catdir( $dir, '..','NotepadDocs' ),
);
my $git      = Git::Repository->new( work_tree => $git_dir );


sub check_authentification {
}

sub create_notepad {
    my $app = shift;

    my $title   = $app->param( 'title' );
    my $passwd  = $app->param( 'notepad_passwd' );
    my $comment = $app->param( 'comment' );
    my $uuid    = $uuid_obj->create_str;
    
    my $notepad_path = File::Spec->catfile( $git_dir, $uuid );

    open my $fh, '>', $notepad_path;
    close $fh;

    chdir $git_dir;

    my $add_output    = Git::Repository->run( add => $uuid );
    my $commit_output = Git::Repository->run( 
        commit => 
        '-m' => 'created notepad', 
        '--author' => 'tester <notepad@perl-services.de>', 
        $uuid,
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
    my $notepad = File::Spec->catfile( $git_dir, $uuid );

    my $content = '';
    if ( $uuid and -f $notepad and open my $fh, '<', $notepad ) {
        local $/;
        $content = <$fh>;
    }

    return $content;
}

sub get_diff {
    my $id     = shift;
    my $params = shift;
    my $opts   = shift;

    my $uuid    = _get_uuid_by_id( $id );
    my $notepad = File::Spec->catfile( $git_dir, $uuid );

    my ($start,$stop) = split /\0/, $params->{history};

    warn "$start -> $stop";
}

sub get_history {
    my $id = shift;

    my $uuid    = _get_uuid_by_id( $id );
    my $notepad = File::Spec->catfile( $git_dir, $uuid );
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
    return 1;
}

sub save_notepad {
}

sub _get_uuid_by_id {
    my $id = shift;

    my $select_sql = 'SELECT uuid FROM articles WHERE id = ? LIMIT 1';
    my $select_sth = $dbh->prepare( $select_sql );
    $select_sth->execute( $id );

    my ($uuid) = $select_sth->fetchrow_array;
    return $uuid;
}

1;
