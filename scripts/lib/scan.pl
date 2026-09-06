use strict;
use warnings;

my $mode = shift @ARGV;
my $dash = qr/$ENV{DASH_BYTES}/;
my $marker = qr/$ENV{DASH_MARKER_BYTES}/;
my %reported;
my $status = 0;

sub escape_data {
	my ($text) = @_;
	$text =~ s/%/%25/g;
	$text =~ s/\r/%0D/g;
	$text =~ s/\n/%0A/g;
	return $text;
}

sub report {
	my ($file, $line, $text) = @_;
	my $kind = $text =~ $marker ? 'marker' : $text =~ $dash ? 'dash' : return;
	my $title = $kind eq 'marker' ? 'Opt-out marker' : 'Unicode dash';
	unless ($reported{$kind}++) {
		print STDERR $kind eq 'marker'
			? "The dash-o" . "k marker no longer suppresses anything and is banned itself.\n"
			: $mode eq 'diff' ? "Unicode dashes on added lines.\n" : "Unicode dashes in this tree.\n";
		print STDERR "Fix the line, or hold the path out with the exclude input.\n\n";
	}
	chomp $text;
	my $path = escape_data($file);
	$text = escape_data($text);
	print STDERR "$path:$line:$text\n";
	if (!$ENV{DASH_STAGED}) {
		$path =~ s/:/%3A/g;
		$path =~ s/,/%2C/g;
		print STDERR "::error file=$path,line=$line,title=${title}::$text\n";
	}
	$status = 1;
}

sub unquote_path {
	my ($path) = @_;
	if ($path =~ s/^"(.*)"$/$1/s) {
		my %escapes = ('a' => "\a", 'b' => "\b", 't' => "\t", 'n' => "\n",
			'v' => "\013", 'f' => "\f", 'r' => "\r", '"' => '"', '\\' => '\\');
		$path =~ s/\\([0-7]{3}|[abtnvfr"\\])/exists $escapes{$1} ? $escapes{$1} : chr(oct($1))/ge;
	}
	$path =~ s{^b/}{} or die "missing destination prefix\n";
	return $path;
}

if ($mode eq 'diff') {
	my ($file, $line, $old_left, $new_left) = ('', 0, 0, 0);
	while (<STDIN>) {
		if ($old_left || $new_left) {
			if (/^\+/ && $new_left) {
				report($file, $line++, substr($_, 1));
				$new_left--;
			} elsif (/^-/ && $old_left) {
				$old_left--;
			} elsif (/^ / && $old_left && $new_left) {
				$old_left--;
				$new_left--;
				$line++;
			} elsif (!/^\\ No newline/) {
				die "invalid diff hunk\n";
			}
			next;
		}
		if (/^\+\+\+ (.+?)\t?\n$/) {
			$file = $1 eq '/dev/null' ? '' : unquote_path($1);
		} elsif (/^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/) {
			($old_left, $line, $new_left) = ($1 // 1, $2, $3 // 1);
		}
	}
	die "incomplete diff hunk\n" if $old_left || $new_left;
} elsif ($mode eq 'zero') {
	RECORD: while (1) {
		my ($file, $line);
		{
			local $/ = "\0";
			$file = <STDIN>;
			last RECORD unless defined $file;
			$line = <STDIN>;
			die "incomplete grep record\n" unless defined $line;
			chomp($file, $line);
		}
		my $text = <STDIN>;
		die "invalid grep record\n" unless $line =~ /^\d+$/ && defined $text;
		report($file, $line, $text);
	}
} else {
	die "unknown scan mode\n";
}

exit $status;
