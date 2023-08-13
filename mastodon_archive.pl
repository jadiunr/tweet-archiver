use strict;
use warnings;
use utf8;
use Getopt::Long;
use JSON::XS;
use YAML::XS;
use Furl;
use File::Basename qw/basename/;
use File::Path qw/mkpath rmtree/;
use Archive::Zip qw/:ERROR_CODES :CONSTANTS/;
use feature qw/say/;

my $opt = sub {
    my %opt;
    my @options = (\%opt, qw/target=s/);
    GetOptions(@options) or die;
    \%opt;
}->();
my $config = YAML::XS::LoadFile 'config.yml';

my $domain = $config->{mastodon}{domain};
my $target_acct_for_search = $opt->{target};
my $target_acct = sub {
    my $target_username = (split /@/, $target_acct_for_search)[0];
    my $target_domain = (split /@/, $target_acct_for_search)[1];
    if ($target_domain eq $domain) {
        return $target_username;
    } else {
        return $target_acct_for_search;
    }
}->();
my $furl = Furl->new(
    agent   => 'Mozilla/5.0 (Windows NT 10.0; rv:68.0) Gecko/20100101 Firefox/68.0',
    headers => ['Authorization' => 'Bearer '. $config->{mastodon}{credentials}{access_token}],
);
my $target_account_id = sub {
    my $search_account_results = (decode_json $furl->get("https://${domain}/api/v2/search?q=${target_acct_for_search}&type=accounts")->content)->{accounts};
    my $target_account = (grep { $_->{acct} eq $target_acct } @$search_account_results)[0];
    return $target_account->{id};
}->();

my $all_statuses = [];
my $max_id;

while (1) {
    my $statuses = decode_json $furl->get(
        "https://${domain}/api/v1/accounts/${target_account_id}/statuses?limit=40&exclude_replies=false&exclude_reblogs=false". (defined($max_id) ? "&max_id=${max_id}" : '')
    )->content;
    last if scalar(@$statuses) < 2;
    push(@$all_statuses, @$statuses);
    say 'Got '. scalar(@$all_statuses). ' statuses.';
    $max_id = $statuses->[-1]{id};
    say 'Next: '. $max_id;
}

say 'Got all '. scalar(@$all_statuses). 'statuses';

{
    open my $fh, ">", 'statuses.json';
    print $fh encode_json $all_statuses;
    close $fh;
}

for my $status (@$all_statuses) {
    next unless ($status->{media_attachments});
    my $status_id = $status->{id};
    for my $medium (@{$status->{media_attachments}}) {
        my $medium_id = $medium->{id};
        my $url = $medium->{url};
        my $filename = basename($url);
        download($url, $filename);
    }
}

my $zip = Archive::Zip->new;
$zip->addFile('statuses.json');
$zip->addTree('media/', 'media/');
if ($zip->writeToFileNamed("mastodon_archive_${target_acct}.zip") == AZ_OK) {
    say "ZIP archive created successfully!";
} else {
    warn "ZIP archive creation failed";
}

unlink 'statuses.json' if -f 'statuses.json';
rmtree 'media/' if -d 'media/';

sub download {
    my $url = shift;
    my $filename = shift;

    my $res = Furl->new->get($url);
    if ($res->code != 200 or $res->content =~ /timeout/) {
        warn "cannot download media: $url";
        return;
    }

    mkpath 'media' unless -d 'media';

    open my $fh, '>', 'media/'. $filename or die "cannot create file: media/$filename";
    print $fh $res->content;
    close $fh;
    return;
}
