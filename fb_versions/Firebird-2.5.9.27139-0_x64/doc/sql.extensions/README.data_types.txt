---------------------
Native SQL data types
---------------------


BIGINT (FB 1.5)
--------------

  Function:
    SQL99-compliant exact numeric type.
	
  Author:
    Dmitry Yemanov <yemanov@yandex.ru>
	
  Syntax rules:
    BIGINT
	
  Storage:
    64-bit, signed
	
  Example(s):
    1. DECLARE VARIABLE VAR1 BIGINT;
    2. CREATE TABLE TABLE1 (FIELD1 BIGINT);
	
  Note(s):
    1. Available in Dialect 3 only.
    2. Quote from the SQL-99 specification:

	SMALLINT, INTEGER, and BIGINT specify the data type exact numeric,
	with scale of 0 (zero) and binary or decimal precision. The choice
	of binary versus decimal precision is implementation-defined, but
	the same radix shall be chosen for all three data types. The precision
	of SMALLINT shall be less than or equal to the precision of INTEGER,
	and the precision of BIGINT shall be greater than or equal to the
	precision of INTEGER.
