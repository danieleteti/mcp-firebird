********************************************************************************
  LIST OF KNOWN INCOMPATIBILITIES
  between versions 2.x and 2.5
********************************************************************************

This document describes all the changes that make v2.5 incompatible in any way
as compared with the previous releases and hence could affect your databases and
applications.

Please read the below descriptions carefully before upgrading your software to
the new Firebird version.

INSTALLATION/CONFIGURATION
--------------------------

  * The database migration process might require some special steps. If the
    database restore fails with the error "malformed string" for you, please
    pay attention to the files in the /misc/upgrade/metadata directory of your
    installation and use the new -fix_fss_data and -fix_fss_metadata command
    line switches of GBAK.

  * Priorly deprecated parameters OldParameterOrdering and CreateInternalWindow
    of firebird.conf are not supported anymore and have been removed.

  * Parameters LockSemCount and LockSignal of firebird.conf don't require tuning
    in the new lock manager implementation, so they have been removed as well.

  * Now Firebird can be built to be relocatable in POSIX environments. That means the
    installation directory is based on Firebird executables and libraries, and libraries
    are not hard-coded loaded from /opt/firebird/lib.
    To enable this feature, --enable-binreloc parameter should be passed to autogen.sh.
    It is expected that this feature is turned on by default in v3.0.
    If you used to copy utilities to different places and rely on libraries being loaded
    from /opt/firebird, that will not work in this mode. The correct approach would be
    the creation of symbolic links.

SQL SYNTAX
--------------------------

  * A number of new reserved keywords are introduced. The full list is available
    here: /doc/sql.extentions/README.keywords. Please ensure your DSQL
    statements and procedure/trigger sources don't contain those keywords as
    identifiers. Otherwise, you'll need to either use them quoted (in Dialect 3
    only) or rename them.

SQL EXECUTION RESULTS
--------------------------

  * Malformed UNICODE_FSS strings and blobs are no longer allowed.

  * Prior to Firebird 2.5 the SET clause of the UPDATE statement assigned
    columns in the user-defined order with the NEW column values being
    immediately accessible to the subsequent assignments. This did not
    conform to the SQL standard. Starting with Firebird 2.5, only OLD column
    values are accessible to all the assignments of the SET clause.
    You can revert back to the legacy behavior via the OldSetClauseSemantics
    parameter of firebird.conf, if required. Please be aware that this parameter
    is provided as a temporary solution for backward compatibility issues and
    will be deprecated in future Firebird versions.

UTILITIES
--------------------------

  * fb_lock_print now requires a database path name in order to print the lock table.
    Use a "-d <path name>" command line switch to specify a database to analyze.

API
--------------------------

  * Inappropriate TPB (transaction parameter buffer) contents is now rejected
    by isc_start_transaction() and isc_start_multiple() API routines. For example,
    it's not allowed to specify "no wait" and non-zero "wait timeout" options
    together, neither it's possible to specify "no record version" mode along
    with "snapshot" transaction isolation mode, etc.

SECURITY
--------------------------

  * Members of administrative Windows groups are not mapped to SYSDBA any more
	by default. Mapping is controlled on per-database basis using SQL command
	ALTER ROLE RDB$ADMIN SET/DROP AUTO ADMIN MAPPING. 
	See README.trusted_authentication for details.
