use strict;
use Data::Dumper;




if($#ARGV == -1){
	print "Try 'perl tomcat.pl --help' for more information.\n";
}
elsif($ARGV[0] eq "--help"){
	print "
	Usage: perl tomcat.pl [command] [file name]
	For example, syntax of command line utility could be:
	perl tomcat.pl --config config.txt --action deploy --application hello-world.war\n
	--action could be:
		check_status	- return status about tomcat
		about 			- return full information about system and programm
		start			- start programm tomcat
		stop			- stop programm tomcat
		restart			- restart programm tomcat
		remove			- this command will remove the tomcat
		install			- this command will install the tomcat
	--config could be:
		-server		- show curent config file of server
			port		- change port, format: from/to. You can change a lot of ports at one times, split with space
			timeout		- change connection Timeout (default \"20000\")
			protocol	- change connection protocol format: from//to. You can change a lot of ports at one times, split with space

			You can send all data  without the keyword, using only keyword the \"--config\"

		-users		- show curent config file of users
			name	- if you send only one word, script add new user (need sending with password and role).
						If you send name in format: name_from/name_to, script will change name
			passwd	- change password. Use only with key \"name\" in format: pass_from/pass_to
			role	- change role. Use only with key \"name\" in format: pass_from/pass_to
			show_users - show all users from config file
	--dump - create backup config files CONFIG and USERS.
				You must add path and name of file for the backup and name of config file wich you are want backup.
				Example: --dump CONFIG ./backup_server.xml
	--backup - restore backup config files CONFIG and USERS.
				You must add path and name of file for the restore backup and name of config file wich you are want restore.
				Example: --dump ./backup_server.xml CONFIG.
";
}
elsif($ARGV[0] eq "--action"){
	my $tmct = TMCT->new();
	if($ARGV[1] eq "status"){
		$tmct->check_status();
		if($tmct->{data}->{install} && $tmct->{data}->{status}){
			print "tomcat installed and work\n";
		}
		elsif($tmct->{data}->{install} && !$tmct->{data}->{status}){
			print "tomcat installed and don't work\n";
		}
		else{
			print "tomcat didn't install\n";
		}
	}
	elsif($ARGV[1] eq "about"){
		$tmct->check_status();
		!$tmct->{data}->{install} ? print "tomcat didn't install\n" : $tmct->about();
	}
	elsif($ARGV[1] eq "start"){
		$tmct->start();
		print "tomcat started\n";
	}
	elsif($ARGV[1] eq "stop"){
		$tmct->stop();
		print "tomcat stoped\n";
	}
	elsif($ARGV[1] eq "restart"){
		$tmct->restart();
		print "tomcat restarted\n";
	}
	elsif($ARGV[1] eq "remove"){
		$tmct->stop();
		$tmct->remove();
		print "tomcat deleted\n";
	}
	elsif($ARGV[1] eq "install"){
		$tmct->check_status();
		if($tmct->{data}->{install}){
			print "tomcat already installed\n";
			$tmct->about();
		}
		else{
			$tmct->install();
			print "tomcat instaled and started\n";
		}
	}
	exit;
}
if($ARGV[0] eq "--config"){
	my $tmct = TMCT->new();
	if($ARGV[1] eq ''){
		$tmct->show_config();
	}
	else{
		my $data_change;
		for(my $i = 2; $i <= $#ARGV; $i++){
			last if $ARGV[$i] eq "--users";
			if($ARGV[$i] =~ m/^\d+\/\d+$/){
				push @{$data_change->{conf}->{port}},$ARGV[$i];
			}
			elsif($ARGV[$i] =~ m/^\d+$/){
				$data_change->{conf}->{timeout} = $ARGV[$i];
			}
			else{
				push @{$data_change->{conf}->{protocol}}, $ARGV[$i];
			}
		}
		$tmct->chage_config($data_change);
	}
}
if($ARGV[0] eq "--users"){
	my $tmct = TMCT->new();
	if($ARGV[1] eq ''){
		$tmct->show_users();
	}
	elsif($ARGV[1] eq 'show_users'){
		$tmct->show_only_users();
		exit;
	}
	else{
		my $data_change;
		for(my $i = 1; $i <= $#ARGV; $i++){
			if($ARGV[$i] eq "passwd"){
				$data_change->{users}->{passwd} = $ARGV[++$i];
			}
			elsif($ARGV[$i] eq "name"){
				$data_change->{users}->{name} = $ARGV[++$i];
			}
			elsif($ARGV[$i] eq "role"){
				$data_change->{users}->{roles} = $ARGV[++$i];
			}
		};
		my $err = 0;
		($err = 1, print "ERROR: Cann't defined name user\n") if !defined $data_change->{users}->{name};
		($err = 1, print "ERROR: Cann't define role or password\n") if $data_change->{users}->{name} !~ m/\// && !defined $data_change->{users}->{roles} && !defined	 $data_change->{users}->{passwd};
		exit if $err;
		$tmct->chage_users ($data_change);
	}
}

if($ARGV[0] eq "--dump"){
	my $tmct = TMCT->new();
	my $err = 0;
	($err = 1, print "ERROR: Cann't define name\n") if $ARGV[1] eq '' ||$ARGV[2] eq '';
	exit if $err;
	$tmct->dump($ARGV[1], $ARGV[2]);
}

if($ARGV[0] eq "--backup"){
	my $tmct = TMCT->new();
	my $err = 0;
	($err = 1, print "ERROR: Cann't define name\n") if $ARGV[1] eq '' ||$ARGV[2] eq '';
	exit if $err;
	$tmct->backup();
}








{
	package TMCT;

	use Socket;
	use Inline::Files;
	use Archive::Zip;


	sub new {
		my $class = shift;
		$class = ref $class if ref $class;
		my $self = bless {}, $class;
		$self->read_setting();
		$self->get_system();
		$self->check_install();
		$self;
	}


	sub get_system{
		my $self = shift;
		if($ENV{"OS"} =~ m/window/i){
			$ENV{"PROCESSOR_ARCHITECTURE"} =~ m/86/ ? $self->{data}->{OS} = "Win86" : $self->{data}->{OS} = "Win64";
		}
		else{
			$self->{data}->{OS} = "linux";
		}
	}

	sub check_install{
		my $self = shift;
		if($self->{data}->{OS} eq "linux"){
			$self->{data}->{install} = `sudo service --status-all|grep tomcat` =~ /tomcat/||0;
		}
		else{
			$self->{data}->{install} = -f "$self->{data}->{setting}->{START}->{$self->{data}->{OS}}";
		}
	}

	sub check_status{
		my $self = shift;
		if($self->{data}->{OS} eq "linux"){
			$self->{data}->{status} = `sudo service --status-all|grep tomcat` =~ /\+/||0;
		}
		else{
			$self->check_install();
			map{
				$_ =~ m/java.exe/ig ? $self->{data}->{status} = 1 : $self->{data}->{status};
			}`WMIC PROCESS get Commandline`;
		}
	}

	sub install{
		my $self = shift;
		if($self->{data}->{OS} eq "linux"){
			system "$self->{data}->{setting}->{INSTALL}->{$self->{data}->{OS}}";
		}
		else{
			$self->download();
			$self->unzip();
			$self->rm_install_file();
		}

	}
	
	sub remove{
		my $self = shift;
		if($self->{data}->{OS} eq "linux"){
			system "$self->{data}->{setting}->{REMOVE}->{$self->{data}->{OS}}";
		}
		else{
			$self->{data}->{setting}->{START}->{$self->{data}->{OS}} =~ m/\\+bin\\+/gi;
			system "rmdir /s /q $`";
			map{
				$self->{data}->{setting}->{$_}->{$self->{data}->{OS}} =~ m/(\\+bin\\+[\w\.]+)/;
				$self->{data}->{setting}->{$_}->{$self->{data}->{OS}} = $1;
			}("START","STOP","RESTART","ABOUT","CONFIG","USERS");
			$self->save_setting();
		}
	}

	sub start{
		my $self = shift;
		system "$self->{data}->{setting}->{START}->{$self->{data}->{OS}}";
	}

	sub restart{
		my $self = shift;
		if($self->{data}->{OS} eq "linux"){
			system "$self->{data}->{setting}->{RESTART}->{$self->{data}->{OS}}";
		}
		else{
			system "$self->{data}->{setting}->{STOP}->{$self->{data}->{OS}}.\\bin\\startup.bat";
		}
	}

	sub stop{
		my $self = shift;
		system "$self->{data}->{setting}->{STOP}->{$self->{data}->{OS}}";
	}

	sub about{
		my $self = shift;
		print "$self->{data}->{setting}->{ABOUT}->{$self->{data}->{OS}}";
		system "$self->{data}->{setting}->{ABOUT}->{$self->{data}->{OS}}";
	}

	sub download{
		my $self = shift;
		my $path = "$self->{data}->{setting}->{INSTALL}->{$self->{data}->{OS}}";
		$path =~ s/http(s?):\/\///;
		$path =~ s/((\w+\.?){2,3})//;
		my $host = $1;
		$path =~ m/([\d\w-.]+.zip)$/i;
		my $filename = $1;
		my @addresses = gethostbyname($host)   or die "Can't resolve: $!\n";
		socket(SOCK, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
		connect(SOCK, sockaddr_in(80, $addresses[4]));
		send (SOCK, "GET $path HTTP/1.0\r\nHOST:$host\r\n\r\n", 0);
		print $ENV{TMP}."\\".$filename,"\n";
		open(FF, '>', $ENV{TMP}."\\".$filename );
			binmode FF;
			my $float = 0;
			my $length;
			while(<SOCK>){
				$length = $1 if ($_ =~ m/Content-Length:\s(\d+)/);
				($float = 1, last) if $_ =~ m/^\r\n$/;
			}
			$/ = undef;
			my $file_contents;
			read(SOCK,$file_contents,$length);
			print FF $file_contents; 
			close(SOCK) or die "Can't close socket: $!\n";
		close(FF) or die "Can't close file: $!\n";
	}

	sub unzip{
		my $self = shift;
		my $path = "$self->{data}->{setting}->{INSTALL}->{$self->{data}->{OS}}";
		$path =~ m/([\d\w-.]+.zip)$/i;
		my $zipname = $1;
		my $zip = Archive::Zip->new($ENV{TMP}."\\".$1);
		my $dir = '';
		foreach my $member ($zip->members){
			if ($member->isDirectory){
				if($dir eq ''){
					$dir =  $member->fileName;
					chop $dir
				}
				else{
					next;
				}
			}
			$member->extractToFileNamed($ENV{TMP}."\\".$member->fileName);
		}
		map{
			$self->{data}->{setting}->{$_}->{$self->{data}->{OS}} =  "$ENV{TMP}\\$dir".$self->{data}->{setting}->{$_}->{$self->{data}->{OS}};
		}("START","STOP","RESTART","ABOUT","CONFIG","USERS");
		$self->save_setting();
		`set "CATALINA_HOME = $ENV{TMP}\\$dir`;
	}

	sub rm_install_file{
		my $self = shift;
		my $path = "$self->{data}->{setting}->{INSTALL}->{$self->{data}->{OS}}";
		$path =~ m/([\d\w-.]+.zip)$/i;
		`del $ENV{TMP}\\$1`;
	}

	sub read_setting{
		my $self = shift;
		open CACHE or die $!;
			my $hash;
			my $key;
			map{
				chop $_;
				if($_ =~ /^\w+$/){
					$key = $_;
				} 
				elsif($_ =~ s/^\t//){
					$_ =~ m/\t+/;
					$hash->{$key}->{$`}=$' if $` ne '';
				}
			}<CACHE>;
			$self->{data}->{setting} = $hash;
		close CACHE or die $!;
	}

	sub save_setting{
		my $self = shift;

		my ($CACHE, $new_data);
		map{
			my $key = $_;
			$new_data .= "$key\n";
			map{
				$new_data .= "\t$_\t$self->{data}->{setting}->{$key}->{$_}\n";
			}keys %{$self->{data}->{setting}->{$key}};
		}keys %{$self->{data}->{setting}};

		open CACHE, ">$CACHE" or die $!;
	    	print CACHE $new_data;
		close CACHE or die $!;
	}

	sub show_config{
		my $self = shift;
		open FF, "<$self->{data}->{setting}->{CONFIG}->{$self->{data}->{OS}}" or die $!;
			print <FF>;
		close FF or die $!;
	}	

	sub show_users{
		my $self = shift;
		open FF, "<$self->{data}->{setting}->{USERS}->{$self->{data}->{OS}}" or die $!;
			print <FF>;
		close FF or die $!;
	}

	sub chage_config{
		my ($self, $change_data) = @_;
		open FF, "<$self->{data}->{setting}->{CONFIG}->{$self->{data}->{OS}}" or die $!;
			my $new_data = "";
	    	map{
	    		my $line = $_;
	    		if($line =~ m/\s+port[=|\s]?"?(\d+)"?/gi){
	    			map{
	    				my ($from, $to) = split "/",$_;
	    				$line =~ s/$from/$to/gi;
	    			}@{$change_data->{conf}->{port}};
	    		}
	    		$line =~ s/connectionTimeout=\"\d+\"/connectionTimeout=\"$change_data->{conf}->{timeout}\"/gi if $change_data->{conf}->{timeout};
	    		if($line =~ m/\s+protocol=/gi){
	    			map{
	    				my ($from, $to) = split "//",$_;
	    				$line =~ s/$from/$to/gi;
	    			}@{$change_data->{conf}->{protocol}};
				}
				$new_data .= $line;
	    	}<FF>;
		close FF or die $!;
		open FF, "+>$self->{data}->{setting}->{CONFIG}->{$self->{data}->{OS}}" or die $!;
			print FF $new_data;
		close FF or die $!;
	}

	sub show_only_users{
		my $self = shift;
		open FF, "<$self->{data}->{setting}->{USERS}->{$self->{data}->{OS}}" or die $!;
			map{
				print $_ if $_ =~ m/\<user\s*username/i;
			}<FF>;
		close FF or die $!;
	}

	sub chage_users{
		my ($self, $change_data) = @_;
		open FF, "<$self->{data}->{setting}->{USERS}->{$self->{data}->{OS}}" or die $!;
			my $new_data = "";
			my $float = 0;
			map{
				if ($_ =~ m/\<user\s*username/i && $change_data->{users}->{name} =~ m/\// && !$float){
					my ($from, $to) = split "\/",$change_data->{users}->{name};
					if($_ =~ m/username="$from"/gi){
						$_ =~ s/username="$from"/username="$to"/gi;
						$_ =~ s/password="[\w\d\<\>\-]+"/password="$change_data->{users}->{passwd}"/gi if $change_data->{users}->{passwd};
						$_ =~ s/roles="[\w\d\,?]+"/roles="$change_data->{users}->{roles}"/gi if $change_data->{users}->{roles};
					}
				}
				elsif(!$float && $_ =~ m/\<user\s*username/i){
					$_ = "\t<user username=\"$change_data->{users}->{name}\" password=\"$change_data->{users}->{passwd}\" roles=\"$change_data->{users}->{roles}\"/>\n".$_;
					$float = 1;
				}
				$new_data .= $_;
			}<FF>;
		close FF or die $!;open FF, "+>$self->{data}->{setting}->{USERS}->{$self->{data}->{OS}}" or die $!;
			print FF $new_data;
		close FF or die $!;
	}

	sub dump{
		my ($self, $file, $path) = @_;
		$file eq "CONFIG" ? $file : $file = "USERS";
		open FF, "<$self->{data}->{setting}->{CONFIG}->{$self->{data}->{OS}}" or die $!;
			open FA, "+>$path" or die $!;
				print FA <FF>;
			close FA or die $!;
		close FF or die $!;
	}

	sub backup{
		my ($self, $path, $file) = @_;
		$file eq "CONFIG" ? $file : $file = "USERS";
		open FF, "<$path" or die $!;
			open FA, "+>$self->{data}->{setting}->{CONFIG}->{$self->{data}->{OS}}" or die $!;
				print FA <FF>;
			close FA or die $!;
		close FF or die $!;
	}

	1;

}







__CACHE__
START
	Win86	\bin\startup.bat
	linux	sudo service tomcat8 start
	Win64	\bin\startup.bat
STOP
	Win86	\bin\shutdown.bat
	linux	sudo service tomcat8 stop
	Win64	\bin\shutdown.bat
REMOVE
	linux	sudo apt-get remove --auto-remove -y tomcat8 && sudo apt-get autoclean && sudo dpkg -P tomcat8 && sudo rm /etc/init.d/tomcat* && perl -e 'map{chop $_;`sudo rm -Rf $_`}`sudo find / -name tomcat8`'
INSTALL
	Win86	http://apache.volia.net/tomcat/tomcat-8/v8.5.28/bin/apache-tomcat-8.5.28-windows-x86.zip
	Win64	http://apache.volia.net/tomcat/tomcat-8/v8.5.28/bin/apache-tomcat-8.5.28-windows-x64.zip
	linux	sudo apt-get install -y tomcat8 && sudo mkdir /usr/share/tomcat8/logs
RESTART
	linux	sudo service tomcat8 restart
	Win64	
ABOUT
	Win86	\bin\version.bat
	linux	sudo /usr/share/tomcat8/bin/version.shh
	Win64	\bin\version.bat
CONFIG
	linux	/etc/tomcat8/server.xml
	Win86	\conf\server.xml
	Win64	\conf\server.xml
USERS
	linux	/etc/tomcat8/tomcat-users.xml
	Win86	\conf\tomcat-users.xml
	Win64	\conf\tomcat-users.xml

