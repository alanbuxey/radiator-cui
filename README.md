Radiator - Chargeable-User-Identity (CUI) support.

The CUI support includes:
1. IdP side  (providing CUI) - a server handling authentication adds 
   the Chargeable-User-Identity attribute. This attribute is sent
   only in response to a CUI request (a Access-Request containing
   a CUI attribute). In eduroam it is required that the CUI request
   also contains an Operator-Name (RFC 5580) attribute. This implementation
   allows for turning on this requirement. The CUI value is computed as an
   MD5 hash of concatenated (inner) User-Name, optional Operator-Name and 
   a local salt value.

2. SP side (requesting CUI) - an eduroam service provider can send CUI
   requests and when a value is returned it may (optionally) use it
   for accounting. Since, in eduroam, it is requred that the CUI request
   also contains the Operator-Name attribute, this implementation allows
   for turning this behaviour on.

The CUI support has been implemented as Radiator hooks and is contained in
the following files:
  
cui.cfg
~~~~~~~
 Contains:
  a. global variables definitions (read from cui_definitions_file),
  b. StartupHook call - to initialize global variables,
  c. optionally for SP side - MySQL connector definition (for temporary 
	records, needed only when it is planned to use CUI in accounting).

cui_definitions_file
~~~~~~~~~~~~~~~~~~~~
 Included by cui.cfg, contains global variables needed by CUI.
 Two variables decide how CUI is supported by an IdP side:
 - CUI_salt - defines the salt value used when the md5 
	hash is created - if this is not set then CUI support for the IdP
        side is turned off.
 - CUI_required_Operator_Name - when set for the IdP and a SP side does not 
	provide the Operator-Name attribute value in Access-Request, then CUI 
        will not be returned; by default this variable is not set.
 Other variables set CUI environment for SP side:
 - CUI_Operator_Name - defines the Operator-Name value added to proxied
	requests - if not set, then Access-Requests will not contain the
	Operator-Name attribute and will not be valid eduroam CUI requests.
 - CUITable, CUIAcct_insert, CUIAcct_delete, CUIAcct_update, CUIAcct_insert -
	define MYSQL operation used to temorary save CUI value (needed only 
	when it is planned to use CUI in accounting)

cui_sql_def
~~~~~~~~~~~
  MySQL script creating the temporary database, needed only when it is planned 
  to use CUI in accounting.


Hooks/CUI.pm
~~~~~~~~~~~~~~~
This file is referenced by as StartupHook, PreProcessingHook, PostProcessingHook and 
PostAuthHook.

- As the PostProcessingHook it is called by IdP or SP side for each 
  Access-Request after all authentication methods have been called 
  and before the reply is sent back. 
  It adjusts Access-Accept reply. If CUI is supported, it creates the md5 
  hash from the User-Name and the local salt, places it as the CUI value in
  the reply packet and inserts the appropriate record with this CUI value
  to the temporary table.

- As the PostAuthHook it is called by IdP side for each request after it
  has been passed to all the AuthBy clauses. It adjusts Access-Accept reply.
  If CUI is supported, it creates the md5 hash from the User-Name and 
  the local salt, places it as the CUI value in the reply packet and inserts
  the appropriate record with this CUI value to the temporary table.
 
- As the PreProcessingHook for Accounting-Request of SP side it checks for
  a matching record in the temporary CUI table and, if found, adds 
  the appropriate CUI value to the packet and updates the temporary record
  with last accounting time.

CONFIGURATION

1. Modify cui.cfg and set appropriate username and password for the
   database you plan to use.

2. Load CUI.pm during Radiator startup:

   StartupHook	sub { require "/etc/radiator/Maja_CUI.pm"; };

3. Modify cui_definitions_file:
 - set CUI_salt to some "random" string,
 - set CUI_Operator_Name to one of your registered DNS domain names.
 - set CUI_required_Operator_Name flag when Operator-Name is required 
   (default - not required)

4. Create a database if it is planned to use CUI in accounting - use the 
   cui_sql_def MySQL script.

5. Make the following modifications of the radius.cfg file:
- include cui.cfg by adding the line

include %D/cui.cfg

- when you act as a SP: add to each Handler or Realm section which proxies request to another server

AddToRequestIfNotExist  Operator-Name="1realm.tld"
AddToRequest            Chargeable-User-Identity=\000

- when you act as a SP and you plan to use CIU in accounting: add 
call to CUI::add in PreProcessingHook to each Handler section,
which matches Accounting-Request e.g.

<Handler Request-Type = Accounting-Request>
AuthBy AccountingResponse
PreProcessingHook sub { CUI::add(@_); };
</Handler>

- when you act as an IdP: add call to CUI::add in PostProcessingHook to each 
Handler or Realm section which handles request locally and should support CUI e.g.

<Handler Realm=eduroam.umk.pl>
AuthBy ....
PostProcessingHook sub { CUI::add(@_); };
</Handler>

- when you act as an IdP: add call to CUI::add in PostAuthHook to each Handler which 
handles packets with TunnelledByPEAP=1, TunnelledByFAST=1 or 
TunnelledByTTLS=1 
(or add such a handler), e.g.

<Handler TunnelledByPEAP=1 >
AuthBy ...
PostAuthHook sub { CUI::add(@_); };
</Handler>
<Handler TunnelledByTTLS=1 >
AuthBy ...
PostAuthHook sub { CUI::add(@_); };
</Handler>
<Handler TunnelledByFAST=1 >
AuthBy ...
PostAuthHook sub { CUI::add(@_); };
</Handler>

