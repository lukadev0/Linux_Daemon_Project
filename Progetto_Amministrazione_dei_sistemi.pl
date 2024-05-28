
use strict;
use warnings;
use POSIX qw(setsid);
use File::Path qw(make_path rmtree);
use File::Temp qw(tempfile);

# percorso per le utenze temporanee
my $temp_dir = "/var/my_temp_users";

# Array per scorrimento nomi directory home
my @home_dirs;


sub create_temp_user {
    my $username = shift;

    # Crea il percorso per l'utente temporaneo
    
    my $user_dir = "$temp_dir/$username";
    my $home_dir = "/home/$username";  

    #directory per l'utente temporaneo
    make_path($user_dir) unless -d $user_dir;

    # directory home dell'utente
    make_path($home_dir) or die "Impossibile creare la directory home: $home_dir $!\n";

    # Aggiungo la directory home all'array
    push @home_dirs, $home_dir;

    #file temp
    my ($fh, $filename) = tempfile(DIR => $user_dir);

    print "\nCreato utente temporaneo: $username\n";
}


sub modify_temp_user_name {
    my ($old_username, $new_username) = @_;

    my $old_user_dir = "$temp_dir/$old_username";
    my $new_user_dir = "$temp_dir/$new_username";
    my $old_home_dir = "/home/$old_username";  
    my $new_home_dir = "/home/$new_username";  

    # Rinomino la directory dell'utente
    if (-d $old_user_dir && !-e $new_user_dir) {
        rename $old_user_dir, $new_user_dir;
        print "\nNome utente modificato da $old_username a $new_username\n";

        # Rinomino anche la directory home dell'utente
        if (-d $old_home_dir && !-e $new_home_dir) {
            rename $old_home_dir, $new_home_dir;
            print "\nDirectory home rinominata da $old_home_dir a $new_home_dir\n";

            # Aggiorna l'array 
            @home_dirs = map { $_ eq $old_home_dir ? $new_home_dir : $_ } @home_dirs;
        } else {
            print "\nErrore: La directory home $old_home_dir non esiste o la nuova directory $new_home_dir è già in uso.\n";
        }
    } else {
        print "\nErrore: L'utente $old_username non esiste o il nuovo nome $new_username è già in uso.\n";
    }
}


sub remove_temp_user {
    my $username = shift;

    my $user_dir = "$temp_dir/$username";
    my $home_dir = "/home/$username";  

    # Rimuovo la directory dell'utente
    if (-d $user_dir) {
        rmtree($user_dir);
        print "\nUtente $username rimosso con successo\n";
    } else {
        print "\nErrore: L'utente $username non esiste.\n";
        return;
    }

    # Rimuovo la directory home dell'utente
    if (-d $home_dir) {
        rmtree($home_dir);
        print "\nDirectory home di $username rimossa con successo\n";

        # Rimuovo la directory home anche dall'array
        @home_dirs = grep { $_ ne $home_dir } @home_dirs;
    } else {
        print "\nErrore: La directory home di $username non esiste.\n";
    }
}

# funzione deamon
sub run_daemon {

    while (1) {
        print "\nScegli un'opzione:\n\n";
        print "1. Crea utenti temporanei\n";
        print "2. Modifica nome utente\n";
        print "3. Rimuovi utente\n";
        print "4. Esci\n\n";

        print "Scelta: ";
        my $choice = <STDIN>;
        chomp $choice;

        if ($choice == 1) {
            print "\nQuanti utenti temporanei vuoi creare? ";
            my $num_users = <STDIN>;
            chomp $num_users;

            # Crea gli utenti temporanei richiesti
            for (my $i = 1; $i <= $num_users; $i++) {
                my $username = "temp_user_" . "$i"; 
                create_temp_user($username);
            }
        } elsif ($choice == 2) {
            print "\nInserisci il nome dell'utente da modificare: ";
            my $old_username = <STDIN>;
            chomp $old_username;
            print "\nInserisci il nuovo nome dell'utente: ";
            my $new_username = <STDIN>;
            chomp $new_username;
            modify_temp_user_name($old_username, $new_username);
        } elsif ($choice == 3) {
            print "\nInserisci il nome dell'utente da rimuovere: ";
            my $username = <STDIN>;
            chomp $username;
            remove_temp_user($username);
        } elsif ($choice == 4) {
            print "\nUscita dal demone.\n";
            # Rimuove tutti i file temporanei e le directory home nella directory /var/my_temp_users
            rmtree($temp_dir);
            rmtree($_) foreach (@home_dirs);
            last;
        } else {
            print "\nScelta non valida. Riprova.\n";
        }
    }
}

run_daemon();