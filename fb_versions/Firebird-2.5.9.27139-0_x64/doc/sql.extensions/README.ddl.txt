DDL enhancements in Firebird v2.
--------------------------------

Author: Claudio Valderrama C. <cvalde at usa.net>

Other DDL enhancements may have their own README file.

1) Ability to signal SQL NULL via a NULL pointer.
(Claudio Valderrama C.)

Previous to Firebird v2, UDF authors only could guess they got a null value,
but they couldn't be sure, so this let to several problems with UDFs. People
ended up assuming that a null string would be passed as an empty string, a null
numeric would be the same than zero and a null date would mean the base date used
by the engine. Of course, for a numeric value, the author only could assume null
if the UDF was done for an environments where it's known that value is not possible
normally. But several UDFs (including ib_udf supplied with FB) assumed an empty
string most likely would mean a null parameter than a string of length zero. The
trick may work with CHAR type (the minimal declared CHAR length is one and would
contain a blank character normally, so a binary zero in the first position would
signal effectively NULL) but it doesn't work with VARCHAR or CSTRING, where length
zero is valid. The other solution was to rely on raw descriptors, but this draws
people to an area with a lot of things to check, more than they would want to tackle.
The biggest problem is that the engine won't obey the declared type for a parameter;
it will simply send whatever data it has for that parameter, so the UDF is left to
decide whether to reject or to try to convert the parameter to the expected data
type. Since UDFs don't have a formal mechanism to signal errors, the returned value
will have to be used as an indicator.
But the basic problem was how to keep the simplicity of the typical declarations
(no descriptors) while at the same time being able to signal null. The engine
normally passed UDF parameters by reference and it means in practical terms to
pass a pointer to the data. By simply passing a null pointer we can tell the UDF
we have SQL NULL, but since we can't afford to crash an unknown number of different
public and private UDFs in use that don't expect NULL, we had to enhance the syntax
to be able to request explicitly NULL handling. Therefore, only UDFs that are able
to deal with the new scenario can request SQL NULL signaling.
To avoid adding more keywords, the NULL keyword is appended to the UDF parameter
type and this is all the required change. Example:
declare external function sample int null returns int by value...;

If you are already using functions from ib_udf and want to take advantage of
null signaling (and null recognition) in some functions, you should connect to
your desired database and run
upgrade/v2/ib_udf_upgrade.sql
and commit afterwards, preferable when no more users are connected to the database.
The code in the listed functions in that script has been modified to recognize
null only when NULL is signaled by the engine. Therefore, starting with FB v2,
rtrim and ltrim no longer assume that an empty string means a NULL string. If you
don't upgrade, the functions won't crash. They simply won't be able to detect NULL.
If you never have used ib_udf and want to do that, you should connect to your desired
database, run
udf/ib_udf2.sql
and commit afterwards, preferable when no more users are connected to the database.
Note the "2" at the end of the name. The original script for FB v1.5 is still
available in the same directory.
The directories "upgrade" and "udf" are inside the home directory of your FB v2
installation.


2) Implemented REVOKE ADMIN OPTION FROM user
(Dmitry Yemanov.)

SYSDBA, the database creator or the owner of an object can grant rights on that
object to other users. However, those rights can be made inheritable, too. By using
WITH GRANT OPTION, the grantor gives the grantee the right to become a grantor of
the same rights in turn. This ability can be removed by the original grantor with
REVOKE GRANT OPTION FROM user.

However, there's a second form that involves roles. Instead of specifying the
same rights for many users (soon it becomes a maintenance nightmare) you can
create a role, assign rights to that role and then grant it to a group of users.
By simply changing the role's rights you affect all those users. By using
WITH ADMIN OPTION, the grantor (typically the role creator) gives the grantee the
right to become a grantor of the same role in turn. Until FB v2, this ability
couldn't be removed unless the original grantor fiddles with system tables directly.
Now, the ability to grant the role can be removed by the original grantor with
REVOKE ADMIN OPTION FROM user.


3) Blob filter's blob types can be declared by mnemonics for known types.
(Alex Peshkov.)

The original allowed syntax for declaring a blob filter was:
declare filter <name> input_type <number> output_type <number>
 entry_point <function_in_library> module_name <library_name>;

The alternative new syntax is:
declare filter <name> input_type <mnemonic> output_type <mnemonic>
 entry_point <function_in_library> module_name <library_name>;

where <mnemonic> refers to a subtype known to the engine. Initially they are
binary, text and others mostly of internal usage, but if the user is enough
brave, having written a new name in rdb$types, that name could be used, since
it's parsed only at declaration time. The engine keeps the numerical value.
Remember, only negative subtype values are meant to be defined by users. To get
the predefined types, do

select * from rdb$types where rdb$field_name = 'RDB$FIELD_SUB_TYPE';

RDB$FIELD_NAME      RDB$TYPE RDB$TYPE_NAME              RDB$DESCRIPTION RDB$SYSTEM_FLAG
=================== ======== ========================== =============== ===============

RDB$FIELD_SUB_TYPE         0 BINARY                          <null>                   1
RDB$FIELD_SUB_TYPE         1 TEXT                            <null>                   1
RDB$FIELD_SUB_TYPE         2 BLR                             <null>                   1
RDB$FIELD_SUB_TYPE         3 ACL                             <null>                   1
RDB$FIELD_SUB_TYPE         4 RANGES                          <null>                   1
RDB$FIELD_SUB_TYPE         5 SUMMARY                         <null>                   1
RDB$FIELD_SUB_TYPE         6 FORMAT                          <null>                   1
RDB$FIELD_SUB_TYPE         7 TRANSACTION_DESCRIPTION         <null>                   1
RDB$FIELD_SUB_TYPE         8 EXTERNAL_FILE_DESCRIPTION       <null>                   1

Examples.

Original declaration:
declare filter pesh input_type 0 output_type 3 entry_point 'f' module_name 'p';
Alternative declaration:
declare filter pesh input_type binary output_type acl entry_point 'f' module_name 'p';

Bizarre declaration for user defined blob subtype. Remember to commit after the insertion:
SQL> insert into rdb$types values('RDB$FIELD_SUB_TYPE', -100, 'XDR', 'test type', 0);
SQL> commit;
SQL> declare filter pesh2 input_type xdr output_type text entry_point 'p2' module_name 'p';
SQL> show filter pesh2;
BLOB Filter: PESH2
        Input subtype: -100 Output subtype: 1
        Filter library is p
        Entry point is p2


4) Allow comments in database objects.
(Claudio Valderrama C.)

Proposed syntax for testing:

COMMENT ON DATABASE IS {'txt'|NULL};
COMMENT ON <basic_type> name IS {'txt'|NULL};
COMMENT ON COLUMN table_or_view_name.field_name IS {'txt'|NULL};
COMMENT ON PARAMETER procedure_name.param_name IS {'txt'|NULL};

An empty literal string '' will act as NULL since the internal code (DYN in this case)
works this way with blobs.

basic_type:
- DOMAIN
- TABLE
- VIEW
- PROCEDURE
- TRIGGER
- EXTERNAL FUNCTION
- FILTER
- EXCEPTION
- GENERATOR
- SEQUENCE
- INDEX
- ROLE
- CHARACTER SET
- COLLATION
- SECURITY CLASS (not implemented because Borland hid them).


5) Allow setting and dropping default values from table fields.
(Claudio Valderrama C.)

Domains allow to change or drop their default. It seems natural that table fields
can be manipulated the same way without going directly to the system tables. Here's
the syntax borrowed from the one to alter domains:

ALTER TABLE t ALTER [COLUMN] c SET DEFAULT default_value;
ALTER TABLE t ALTER [COLUMN] c DROP DEFAULT;

Notes:
- Array fields cannot have a default value.
- If you change the type of a field, the default may remain in place. This is
because a field can be given the type of a domain with a default but the field
itself can override such domain. On the other hand, the field can be given a
type directly in whose case the default belongs logically to the field (albeit
the information is kept on an implicit domain created behind scenes).


6) New blob filter restriction.
(Dmitry Yemanov)

In FB2, the pair (input subtype, output subtype) must be unique for blob filter
declarations. This fix stops ambiguity in deciding which blob filter will be
executed to go from input type X to output type Z. If you have such problem in
databases created with earlier versions and you have a backup for them that want
to restore in FB2, expect to see your database restore being rejected by FB2.


7) ALTER computed fields
(Adriano dos Santos Fernandes)

Syntax:

alter table ...
    alter <field> [type <data type>] computed by (<expression>);

Notes:
- You cannot alter a non-COMPUTED field to COMPUTED and vice-versa.

Example:

create table test (
    n integer,
    dn computed by (n * 2)
);

alter table test
    alter dn computed by (n + n);


8) ALTER VIEW
(Adriano dos Santos Fernandes)

Function:

Ability to alter a view without the need to recreate (drop and create) the view and all of it's
dependencies.

Syntax:

{ create [ or alter ] | alter } view <view_name> [ ( <field list> ) ]
    as <select statement>

Example:

create table users (
    id integer,
    name varchar(20),
    passwd varchar(20)
);

create view v_users as
    select name from users;

alter view v_users (id, name) as
    select id, name from users;


9) GRANT/REVOKE rights GRANTED BY specified user
(Alex Peshkoff)

Function:

Makes it possible to specify non-default (which is CURRENT_USER) grantor in GRANT and REVOKE 
commands.

Syntax:

grant <right> to <object> [ { granted by | as } [ user ] <username> ]
revoke <right> from <object> [ { granted by | as } [ user ] <username> ]

Example (as SYSDBA):

create role r1;
grant r1 to user1 with admin option;
grant r1 to public granted by user1;

(in isql)
show grant;
/* Grant permissions for this database */
GRANT R1 TO PUBLIC GRANTED BY USER1
GRANT R1 TO USER1 WITH ADMIN OPTION

Misc:
GRANTED BY form of clause is recommended by SQL standard. AS is supported by some other 
servers (Informix), and is added for better compatibility.


10) ALTER CHARACTER SET
(Adriano dos Santos Fernandes)

Function:

Allows to change the default collation of a character set.

The default collation is used when table columns are created with a given character set (explicit
or implicit through the database default character set) without a collation specified.
String constants also uses the default collation of the connection character set.

Syntax:

alter character set <charset_name>
    set default collation <collation_name>

Example:

create database 'peoples.fdb'
    default character set win1252;
 
alter character set win1252
    set default collation win_ptbr;
 
create table peoples (
    id integer,
    name varchar(50)  -- will use the database default character set and the win1252 default collation
);
 
insert into peoples values (1, 'adriano');
insert into peoples values (2, 'ADRIANO');
 
-- will retrieve both records because win_ptbr is case insensitive
select * from peoples where name like 'A%';


11) Default collation in CREATE DATABASE
(Adriano dos Santos Fernandes)

Function:

Specify the default collation of the default character set. See also ALTER CHARACTER SET.

Syntax:

create database <file name>
    [ page_size <page size> ]
    [ length = <length> ]
    [ user <user name> ]
    [ password <user password> ]
    [ set names <charset name> ]
    [ default character set <charset name> [ collation <collation name> ] ]
    [ difference file <file name> ]

Example:

create database 'test.fdb'
    default character set win1252 collation win_ptbr;


12) REVOKE ALL ON ALL
(Alex Peshkoff)

Function:

When user is removed from security database (or any other authentication source),
it's useful to revoke his access to any object in database. 

Syntax:

REVOKE ALL ON ALL FROM [USER] username
REVOKE ALL ON ALL FROM [ROLE] rolename

Example:

# gsec -del guest
# isql employee
fbs bin # ./isql employee
Database:  employee
SQL> REVOKE ALL ON ALL FROM USER guest;
SQL>

