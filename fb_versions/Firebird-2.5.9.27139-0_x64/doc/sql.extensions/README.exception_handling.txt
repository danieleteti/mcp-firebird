------------------
Exception handling
------------------

The common syntax rules for EXCEPTION statement is:

  EXCEPTION [[name] [value]];


Run-time exception messages (FB 1.5)
------------------------------------

  Function:
    Allows to throw exceptions with text message
    defined at runtime.

  Author:
    Dmitry Yemanov <yemanov@yandex.ru>

  Syntax rules:
    EXCEPTION <exception_name> <message_value>;

  Scope:
    PSQL

  Example(s):
    1. EXCEPTION E_EXCEPTION_1 'Error!';
    2. EXCEPTION E_EXCEPTION_2 'Wrong type for record with ID=' || new.ID;


Exception re-raise semantics (FB 1.5)
-------------------------------------

  Function:
    Allows to re-initiate catched exception.

  Author:
    Digitman <digitman@hotbox.ru>

  Syntax rules:
    EXCEPTION;

  Scope:
    PSQL, context of the exception handling block

  Example(s):
    BEGIN
      ...
    WHEN SQLCODE -802 DO
      EXCEPTION E_ARITH_EXCEPT;
    WHEN SQLCODE -802 DO
      EXCEPTION E_KEY_VIOLATION;
    WHEN ANY DO
      EXCEPTION;
    END

  Note(s):
    Evaluates to no-op if used outside the exception handling block.


Run-time error codes (FB 1.5)
-----------------------------

  Function:
    Allows to get a numeric error code for the catched exception.

  Author:
    Dmitry Yemanov <yemanov@yandex.ru>

  Syntax rules:
    SQLCODE / GDSCODE;

  Scope:
    PSQL, context of the exception handling block

  See also:
    README.context_variables
