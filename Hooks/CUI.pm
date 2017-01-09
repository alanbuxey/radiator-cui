package CUI;

use strict;
use Digest::MD5 qw(md5_hex);
use Radius::Util qw(inet_ntop);
use POSIX;
use Time::Local;
use Data::Dumper;

sub add
{
# this code act as PostProcessinigHook 
    my $request;
    my $reply;
    my $outerrequest;

#    &main::log($main::LOG_DEBUG, "CUI: byl jsem tady");

# PostProcessinigHook handling Access-Accept (IdP)
    $request = ${$_[0]};
    $reply = ${$_[1]};
    my $innerauth = "";
    if (defined ${$_[2]} ) 
    {
# PostAuthHook handling Access-Accept (IdP)
	if ( ${$_[2]} == $main::ACCEPT ) 
        {
		$innerauth = $request->{EAPIdentity};
		$innerauth = $request->getUserName() unless defined $innerauth;
	}
    }
    if (defined($request->{outerRequest}) and (keys %{$request->{outerRequest}})) {
      $outerrequest = $request->{outerRequest}
    };

    my $client_addr;
    if ( $outerrequest ) 
    {
	$client_addr = $outerrequest->{RecvFromAddress};
    } 
    else 
    {
	$client_addr = $request->{RecvFromAddress};
    } 
    my $client_name = Radius::Util::inet_ntop($client_addr);

    my $replycode = $reply->code;

# our CUI environment
    my $authby_handle = Radius::AuthGeneric::find('CUI');
    my $cuiacct = &main::getVariable('CUI_accounting');
    my $cuitable = &main::getVariable('CUITable');
    if ($authby_handle && $cuiacct) {
        my $cuiacct_select = &main::getVariable('CUIAcct_select');
        if ($request->code eq 'Accounting-Request') 
        {    
  	    my @cui = $request->get_attr('Chargeable-User-Identity');
# nothing to do if CUI is set 
  	    return if ( ($#cui == 0) && (length($cui[0]) > 1) );
  	    #SEMIK ??? return if ($#cui < 0);
# get CUI value
  	    my $query = sprintf(&main::getVariable('CUIAcct_select'), $cuitable, $client_name, $request->get_attr('Calling-Station-Id'), $request->get_attr('User-Name'));
  	    my $sth = $authby_handle->prepareAndExecute($query);
  	    my @result = $sth->fetchrow_array();
  	    if ($#result==0) 
	    {
# found CUI value
   		my $statustype = $request->get_attr('Acct-Status-Type');
   		$request->change_attr('Chargeable-User-Identity', $result[0]);
   		if ( ($statustype =~ /start/i) || ($statustype =~ /alive/i) ) 
		{
# update the CUI record 
    			$query = sprintf(&main::getVariable('CUIAcct_update'), $cuitable, $client_name, $request->get_attr('Calling-Station-Id'), $request->get_attr('User-Name'), $result[0]);
   		} 
		elsif ($statustype =~ /stop/i) 
		{
# remove the CUI record 
    			$query = sprintf(&main::getVariable('CUIAcct_delete'), $cuitable, $client_name, $request->get_attr('Calling-Station-Id'), $request->get_attr('User-Name'), $result[0]);
   		}
   		$sth = $authby_handle->prepareAndExecute($query);
  	    }    
            return;
        }
    }

    my $r;
    if ( $outerrequest ) 
    {
      $r = $outerrequest;
    } 
    else 
    {
      return if ($request->{EAPTypeName} eq "TTLS") ;
      $r = $request;
    }
    if ( ($replycode eq "Access-Accept") || ($innerauth ne "") ) 
    {

     my @cui = $r->get_attr('Chargeable-User-Identity');
     my $user = $request->get_attr('User-Name');
     my $user;
     if ($innerauth ne "") 
     {
	$user = $innerauth;
     } 
     else
     {
     	$user = $request->get_attr('User-Name');
     }

     my $opname = $r->get_attr('Operator-Name');
     my $isopname = 1;
     if ( !$opname ) 
     {
       	if (! &main::getVariable('CUI_required_Operator_Name') ) 
	{
		$opname = "";
       	}
	else
	{
		$isopname = 0;
	}
     }
     my $cuisalt = &main::getVariable('CUI_salt');
     if ( $isopname && ($outerrequest || ($request->{EAPTypeName} eq "TLS") || ($request->{EAPTypeName} eq "PWD") ) &&
          ($#cui==0) && (length($cui[0]) <= 1) ) 
     {
      		$reply->add_attr('Chargeable-User-Identity', md5_hex($cuisalt.lc($user).$opname));
     }
     my @proxystate = $r->get_attr("Proxy-State");
     my  $cui = $reply->get_attr('Chargeable-User-Identity');

     if ( ($#proxystate==-1) && $cui && $authby_handle ) 
     {
      if ( $cuiacct && $cui ) 
      {
# update the cui table
        my $csid = $r->get_attr('Calling-Station-Id');
        my $user = $r->get_attr('User-Name');
        my $query = sprintf(&main::getVariable('CUIAcct_insert'), $cuitable, $client_name, $csid, $user, $cui, $cui);
	#&main::log($main::LOG_DEBUG, "CUI: query=$query");
        my $sth = $authby_handle->prepareAndExecute($query);
      }
     }
    }
    return;
};

# Configurable variables
my $filename;
if ($filename = &main::getVariable('CUIDefsFilename'))
{
    $filename = &Radius::Util::format_special($filename);
}
else
{
    $filename = '/etc/radiator/cui_definitions_file';
}

open(FILE, $filename) ||
    (&main::log($main::LOG_ERR, "Could not open $filename")
     && return);
my $record;
while (<FILE>)
{
    s/\\\n//g;
    next if /^#/ || /^\s*$/;
    chomp($record = $_);
    my @el = split('=',$record,2);
    if ( $#el == 1 ) {
	&main::setVariable($el[0], $el[1]);
    }
};

&main::log($main::LOG_DEBUG, "CUI: Hopefuly initialized");

1;
