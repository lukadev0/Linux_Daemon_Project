#!/usr/bin/perl
use strict;
use warnings;
use Tk;
use Proc::Daemon;
use File::Temp qw(tempfile);
use File::Path qw(make_path remove_tree);
use POSIX qw(getpwuid);

my $user_file = "/var/temp_users_file.txt"; # Specifica un percorso diverso da /tmp
my %users;
my $mw;


# Carica gli utenti esistenti dal file
load_users();

# Creazione dell'interfaccia TK
$mw = MainWindow->new;
$mw->title("Gestione Utenti Temporanei");

my $frm_create = $mw->Frame()->pack(-side => 'top');
$frm_create->Label(-text => "Nome Utente")->pack(-side => 'left');
my $ent_username = $frm_create->Entry()->pack(-side => 'left');
$frm_create->Label(-text => "Permessi")->pack(-side => 'left');
my $ent_permissions = $frm_create->Entry()->pack(-side => 'left');
$frm_create->Button(
    -text => "Crea",
    -command => sub {
        my $username = $ent_username->get();
        my $permissions = $ent_permissions->get();
        create_user($username, $permissions);
    }
)->pack(-side => 'left');

my $frm_modify = $mw->Frame()->pack(-side => 'top');
$frm_modify->Label(-text => "Vecchio Nome")->pack(-side => 'left');
my $ent_old_username = $frm_modify->Entry()->pack(-side => 'left');
$frm_modify->Label(-text => "Nuovo Nome")->pack(-side => 'left');
my $ent_new_username = $frm_modify->Entry()->pack(-side => 'left');
$frm_modify->Label(-text => "Nuovi Permessi")->pack(-side => 'left');
my $ent_new_permissions = $frm_modify->Entry()->pack(-side => 'left');
$frm_modify->Button(
    -text => "Modifica",
    -command => sub {
        my $old_username = $ent_old_username->get();
        my $new_username = $ent_new_username->get();
        my $new_permissions = $ent_new_permissions->get();
        modify_user($old_username, $new_username, $new_permissions);
    }
)->pack(-side => 'left');

my $frm_delete = $mw->Frame()->pack(-side => 'top');
$frm_delete->Label(-text => "Nome Utente")->pack(-side => 'left');
my $ent_del_username = $frm_delete->Entry()->pack(-side => 'left');
$frm_delete->Button(
    -text => "Elimina",
    -command => sub {
        my $username = $ent_del_username->get();
        delete_user($username);
    }
)->pack(-side => 'left');

my $frm_show = $mw->Frame()->pack(-side => 'top');
$frm_show->Button(
    -text => "Mostra Lista",
    -command => \&show_user_list
)->pack(-side => 'left');

$mw->Button(
    -text => "Spegni Demone",
    -command => sub { shutdown_daemon(); }
)->pack(-side => 'top');

MainLoop();

Proc::Daemon::Init; # Inizializza il demone


# Funzione per salvare gli utenti nel file temporaneo
sub save_users {
    open(my $fh, '>', $user_file) or die "Cannot open file: $!";
    foreach my $username (keys %users) {
        my $home = $users{$username}{home};
        my $permissions = $users{$username}{permissions};
        print $fh "$username:$home:$permissions\n";
    }
    close($fh);
}

# Funzione per caricare gli utenti dal file temporaneo
sub load_users {
    %users = ();
    open(my $fh, '<', $user_file) or return;
    while (my $line = <$fh>) {
        chomp $line;
        my ($username, $home, $permissions) = split /:/, $line;
        $users{$username} = { home => $home, permissions => $permissions };
    }
    close($fh);
}

# Funzione per creare un utente temporaneo
sub create_user {
    my ($username, $permissions) = @_;

    if (getpwnam($username)) {
        # Se l'utente esiste già, mostra un messaggio di avviso
        my $message = "L'utente '$username' esiste gia' nel sistema.";
        $mw->messageBox(-message => $message, -type => 'ok');
        return;
    }


    my $home = "/home/temp_$username";
    system("useradd -m -d $home $username");
    system("chmod $permissions $home");
    $users{$username} = { home => $home, permissions => $permissions };
    save_users();
}

# Funzione per modificare un utente temporaneo
sub modify_user {
    my ($old_username, $new_username, $new_permissions) = @_;
    my $old_home = $users{$old_username}{home};
    my $new_home = "/home/temp_$new_username";
    system("usermod -l $new_username -d $new_home -m $old_username");
    system("chmod $new_permissions $new_home");
    delete $users{$old_username};
    $users{$new_username} = { home => $new_home, permissions => $new_permissions };
    save_users();
    update_user_in_groups($old_username, $new_username);
}

sub update_user_in_groups {
    my ($old_username, $new_username) = @_;
    open(my $fh, '<', '/etc/group') or die "Cannot open /etc/group: $!";
    my @lines = <$fh>;
    close($fh);

    open($fh, '>', '/etc/group') or die "Cannot open /etc/group: $!";
    foreach my $line (@lines) {
        $line =~ s/\b$old_username\b/$new_username/g;
        print $fh $line;
    }
    close($fh);
}


# Funzione per eliminare un utente temporaneo
sub delete_user {
    my ($username) = @_;
    my $home = $users{$username}{home};
    system("userdel -r $username");
    remove_tree($home);

    # Rimuove lo spool di posta solo se presente
    if (-e "/var/mail/$username") {
        system("rm -rf /var/mail/$username");
    }

    delete_user_from_groups($username);
    delete $users{$username};
    save_users();
}


# Funzione per rimuovere un utente da tutti i gruppi
sub delete_user_from_groups {
    my ($username) = @_;
    open(my $fh, '<', '/etc/group') or die "Cannot open /etc/group: $!";
    my @lines = <$fh>;
    close($fh);

    open($fh, '>', '/etc/group') or die "Cannot open /etc/group: $!";
    foreach my $line (@lines) {
        $line =~ s/,$username,/,/g;
        $line =~ s/,$username//g;
        $line =~ s/$username,//g;
        print $fh $line;
    }
    close($fh);
}

# Funzione per spegnere il demone
sub shutdown_daemon {
    foreach my $username (keys %users) {
        delete_user($username);
    }
    unlink $user_file;
    exit 0;
}

# Funzione per mostrare la lista degli utenti
sub show_user_list {
    my $list_window = $mw->Toplevel();
    $list_window->title("Lista Utenti Temporanei");

    my $text = $list_window->Scrolled("Text")->pack(-expand => 1, -fill => 'both');

    foreach my $username (keys %users) {
        my $home = $users{$username}{home};
        my $permissions = $users{$username}{permissions};
        $text->insert('end', "Utente: $username, Home: $home, Permessi: $permissions\n");
    }
}
