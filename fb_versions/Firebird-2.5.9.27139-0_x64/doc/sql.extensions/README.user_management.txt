SQL Language Extension: CREATE/ALTER/DROP USER

   Implements capability to manage users from regular database attachment.

Author:
   Alex Peshkoff <peshkoff@mail.ru>

Syntax is:

   CREATE USER name {PASSWORD 'password'} [FIRSTNAME 'firstname'] [MIDDLENAME 'middlename'] [LASTNAME 'lastname'];
   ALTER USER name [PASSWORD 'password'] [FIRSTNAME 'firstname'] [MIDDLENAME 'middlename'] [LASTNAME 'lastname'];
   DROP USER name;

Description:

Makes it possible to add, modify and delete users in security database using SQL language. 

Firebird 2.5 has no way to make it possible to setup different security databases. But since 3.0 
this is supposed to become standard feature, therefore it's highly recommended (though currently the 
result does not change) to modify users being connected to really that database, where modification 
is required. 

CREATE and DROP clauses are available only for SYSDBA (or other user, granted RDB$ADMIN role in 
security database). Ordinary user can ALTER his own password and/or wide names. Attempt to modify
another user will fail.

At least one of PASSWORD, FIRSTNAME, MIDDLENAME or LASTNAME must be present in ALTER USER statement.
Also notice that PASSWORD clause is required when creating new user.

Sample:

   CREATE USER alex PASSWORD 'test';
   ALTER USER alex FIRSTNAME 'Alex' LASTNAME 'Peshkoff';
   ALTER USER alex PASSWORD 'IdQfA';
   DROP USER alex;
