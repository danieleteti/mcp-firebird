SET SQL DIALECT 3;
/* (6) Table with NO primary key */
CREATE TABLE NOPK_LOG (
  LOG_TS    TIMESTAMP,
  MESSAGE   VARCHAR(200)
);

/* (8) Over-indexed write-heavy table: 6 single-column indexes */
CREATE TABLE OVERIDX (
  ID    INTEGER NOT NULL PRIMARY KEY,
  A INTEGER, B INTEGER, C INTEGER, D INTEGER, E INTEGER, F INTEGER
);
CREATE INDEX IDX_OVERIDX_A ON OVERIDX (A);
CREATE INDEX IDX_OVERIDX_B ON OVERIDX (B);
CREATE INDEX IDX_OVERIDX_C ON OVERIDX (C);
CREATE INDEX IDX_OVERIDX_D ON OVERIDX (D);
CREATE INDEX IDX_OVERIDX_E ON OVERIDX (E);
CREATE INDEX IDX_OVERIDX_F ON OVERIDX (F);

/* (7) Stale statistics: index created on the EMPTY table, rows inserted afterwards. */
CREATE TABLE STALE_T (
  ID   INTEGER NOT NULL PRIMARY KEY,
  CODE INTEGER
);
CREATE INDEX IDX_STALE_CODE ON STALE_T (CODE);
COMMIT;

SET TERM ^ ;
EXECUTE BLOCK AS DECLARE I INTEGER = 0; BEGIN
  WHILE (I < 4000) DO BEGIN
    INSERT INTO STALE_T (ID, CODE) VALUES (:I, :I);
    INSERT INTO OVERIDX (ID, A, B, C, D, E, F) VALUES (:I, MOD(:I,2), MOD(:I,3), :I, :I, :I, :I);
    I = I + 1;
  END
END^
SET TERM ; ^
COMMIT;

/* (10) Non-sargable: query will use LIKE '%foo' / fn(col); table just needs data */
CREATE TABLE NSARG_T (ID INTEGER NOT NULL PRIMARY KEY, NAME VARCHAR(100));
CREATE INDEX IDX_NSARG_NAME ON NSARG_T (NAME);

/* (11) Implicit conversion: INTEGER column queried with a string literal */
CREATE TABLE CONV_T (ID INTEGER NOT NULL PRIMARY KEY, CODE INTEGER);
CREATE INDEX IDX_CONV_CODE ON CONV_T (CODE);

/* (12) Oversized index key: long VARCHAR indexed (key-size pressure on small page sizes) */
CREATE TABLE BIGKEY_T (ID INTEGER NOT NULL PRIMARY KEY, LABEL VARCHAR(800) CHARACTER SET NONE);
CREATE INDEX IDX_BIGKEY_LABEL ON BIGKEY_T (LABEL);
COMMIT;

/* (13) A DESCENDING index on the same column as the ascending primary key. It is NOT a
   duplicate: only it can serve ORDER BY ID DESC / MAX(ID) without a sort, so advising a drop
   would take a working index away. */
CREATE DESCENDING INDEX IDX_ORDERS_ID_DESC ON ORDERS (ORDER_ID);
COMMIT;

/* (14) The index advisor's own table: every column unindexed, and skewed on purpose so that
   each rule has a positive and a negative case in the same table.
     STATE  - 90% 'CLOSED', 10% 'ACTIVE'. Filtering on 'CLOSED' returns most of what it reads:
              the scan is the right plan and no index should be suggested. Filtering on
              'ACTIVE' alongside another predicate is the partial-index shape.
     TAG    - 200 distinct values, ~0.5% each: an index pays here.
     LABEL  - queried through UPPER(), which no plain index can serve.
   20 000 rows, comfortably above the 5 000-record floor below which an index changes nothing
   measurable, on every engine in the matrix. */
CREATE TABLE SKEWED (
  ID     INTEGER NOT NULL PRIMARY KEY,
  STATE  VARCHAR(10),
  TAG    VARCHAR(20),
  LABEL  VARCHAR(40)
);
COMMIT;

SET TERM ^ ;
EXECUTE BLOCK AS DECLARE I INTEGER = 0; BEGIN
  WHILE (I < 20000) DO BEGIN
    INSERT INTO SKEWED (ID, STATE, TAG, LABEL) VALUES (
      :I,
      CASE WHEN MOD(:I,10) = 0 THEN 'ACTIVE' ELSE 'CLOSED' END,
      'T' || MOD(:I,200),
      'label_' || :I);
    I = I + 1;
  END
END^
SET TERM ; ^
COMMIT;

/* (15) An index the optimizer refuses to use because it is costing it against numbers that
   were true once. Built and analyzed while K held two distinct values, then loaded with 19 000
   unique ones and never analyzed again: stored selectivity says 0.5 (one value in two), the
   column really holds one value in twenty thousand. The advisor must answer SET STATISTICS,
   not CREATE INDEX — the index the query wants is already there. */
CREATE TABLE STALEIDX (ID INTEGER NOT NULL PRIMARY KEY, K INTEGER);
CREATE INDEX IDX_STALEIDX_K ON STALEIDX (K);
COMMIT;

SET TERM ^ ;
EXECUTE BLOCK AS DECLARE I INTEGER = 0; BEGIN
  WHILE (I < 1000) DO BEGIN
    INSERT INTO STALEIDX (ID, K) VALUES (:I, MOD(:I,2));
    I = I + 1;
  END
END^
SET TERM ; ^
COMMIT;
SET STATISTICS INDEX IDX_STALEIDX_K;
COMMIT;

SET TERM ^ ;
EXECUTE BLOCK AS DECLARE I INTEGER = 1000; BEGIN
  WHILE (I < 20000) DO BEGIN
    INSERT INTO STALEIDX (ID, K) VALUES (:I, :I);
    I = I + 1;
  END
END^
SET TERM ; ^
COMMIT;

/* (24) Privileges held by PUBLIC: not a group somebody joined, but every account that can
   attach — including the ones created after the grant. The second one writes. */
GRANT SELECT ON CUSTOMERS TO PUBLIC;
GRANT INSERT, UPDATE ON NOPK_LOG TO PUBLIC;

/* (25) Delegation: a grantee that can widen access without a DBA seeing it. */
GRANT SELECT ON ORDERS TO REPORT_USER WITH GRANT OPTION;

/* (26) A role nobody is a member of: either dead, or the accounts that should hold its
   privileges are holding direct grants instead. Next to it, a role that is used as intended:
   the audit must flag the first and leave the second alone. */
CREATE ROLE DEAD_ROLE;
CREATE ROLE REPORT_ROLE;
GRANT REPORT_ROLE TO REPORT_USER;
COMMIT;
