/*
 * The contents of this file are subject to the Interbase Public
 * License Version 1.0 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy
 * of the License at http://www.Inprise.com/IPL.html
 *
 * Software distributed under the License is distributed on an
 * "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
 * or implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * The Original Code was created by Inprise Corporation
 * and its predecessors. Portions created by Inprise Corporation are
 * Copyright (C) Inprise Corporation.
 *
 * All Rights Reserved.
 * Contributor(s): ______________________________________.
 */
set sql dialect 1;
create database "employe2.fdb";
/*
 *	Currency cross rates:  convert one currency type into another.
 *
 *	Ex.  5 U.S. Dollars = 5 * 1.3273 Canadian Dollars
 */

CREATE TABLE cross_rate
(
    from_currency   VARCHAR(10) NOT NULL,
    to_currency     VARCHAR(10) NOT NULL,
    conv_rate       FLOAT NOT NULL,	
    update_date     DATE,

    PRIMARY KEY (from_currency, to_currency)
);

INSERT INTO cross_rate VALUES ('Dollar', 'CdnDlr',  1.3273,  '11/22/93');
INSERT INTO cross_rate VALUES ('Dollar', 'FFranc',  5.9193,  '11/22/93');
INSERT INTO cross_rate VALUES ('Dollar', 'D-Mark',  1.7038,  '11/22/93');
INSERT INTO cross_rate VALUES ('Dollar', 'Lira',    1680.0,  '11/22/93');
INSERT INTO cross_rate VALUES ('Dollar', 'Yen',     108.43,  '11/22/93');
INSERT INTO cross_rate VALUES ('Dollar', 'Guilder', 1.9115,  '11/22/93');
INSERT INTO cross_rate VALUES ('Dollar', 'SFranc',  1.4945,  '11/22/93');
INSERT INTO cross_rate VALUES ('Dollar', 'Pound',   0.67774, '11/22/93');
INSERT INTO cross_rate VALUES ('Pound',  'FFranc',  8.734,   '11/22/93');
INSERT INTO cross_rate VALUES ('Pound',  'Yen',     159.99,  '11/22/93');
INSERT INTO cross_rate VALUES ('Yen',    'Pound',   0.00625, '11/22/93');
INSERT INTO cross_rate VALUES ('CdnDlr', 'Dollar',  0.75341, '11/22/93');
INSERT INTO cross_rate VALUES ('CdnDlr', 'FFranc',  4.4597,  '11/22/93');

