/*
 *  The contents of this file are subject to the Initial
 *  Developer's Public License Version 1.0 (the "License");
 *  you may not use this file except in compliance with the
 *  License. You may obtain a copy of the License at
 *  http://www.ibphoenix.com/main.nfs?a=ibphoenix&page=ibp_idpl.
 *
 *  Software distributed under the License is distributed AS IS,
 *  WITHOUT WARRANTY OF ANY KIND, either express or implied.
 *  See the License for the specific language governing rights
 *  and limitations under the License.
 *
 *  The Original Code was created by Adriano dos Santos Fernandes
 *  for the Firebird Open Source RDBMS project.
 *
 *  Copyright (c) 2008 Adriano dos Santos Fernandes <adrianosf@gmail.com>
 *  and all contributors signed below.
 *
 *  All Rights Reserved.
 *  Contributor(s): ______________________________________.
 *					Alex Peshkoff
 */

#include "UdrCppExample.h"

using namespace Firebird;


//------------------------------------------------------------------------------


/***
create procedure gen_dates (
    start_date timestamp with time zone not null,
    n_days integer not null
) returns (
    out_date timestamp with time zone not null
)
    external name 'udrcpp_example!gen_dates'
    engine udr;
***/
FB_UDR_BEGIN_PROCEDURE(gen_dates)
	// Without InMessage/OutMessage definitions, messages will be byte-based.

	// Procedure variables.
	unsigned inOffsetStartDate, inOffsetNDays, outNullOffset, outOffset;

	// Get offsets once per procedure.
	FB_UDR_CONSTRUCTOR
	{
		AutoRelease<IMessageMetadata> inMetadata(metadata->getInputMetadata(status));
		inOffsetStartDate = inMetadata->getOffset(status, 0);
		inOffsetNDays = inMetadata->getOffset(status, 1);
//			printf("SQLtype in = %d\n", inMetadata->getType(status, 0));

		AutoRelease<IMessageMetadata> outMetadata(metadata->getOutputMetadata(status));
		outNullOffset = outMetadata->getNullOffset(status, 0);
		outOffset = outMetadata->getOffset(status, 0);
//			printf("SQLtype out = %d\n", outMetadata->getType(status, 0));
	}

	/*** Procedure destructor.
	FB_UDR_DESTRUCTOR
	{
	}
	***/

	FB_UDR_EXECUTE_PROCEDURE
	{
		counter = *(ISC_LONG*) (in + procedure->inOffsetNDays);
		run = *(ISC_TIMESTAMP_TZ*) (in + procedure->inOffsetStartDate);

		*(ISC_SHORT*) (out + procedure->outNullOffset) = FB_FALSE;
	}

	// After procedure's execute definition, starts the result set definition.

	FB_UDR_FETCH_PROCEDURE
	{
		if (--counter < 0)
			return false;

		*(ISC_TIMESTAMP_TZ*) (out + procedure->outOffset) = run;
		run.utc_timestamp.timestamp_date++;
		return true;
	}

	/*** ResultSet destructor.
	~ResultSet()
	{
	}
	***/

	// ResultSet variables.
	ISC_LONG counter;
	ISC_TIMESTAMP_TZ run;
FB_UDR_END_PROCEDURE


/***
create procedure gen_dates2 (
    start_date timestamp with time zone not null,
    n_days integer not null
) returns (
    out_date timestamp with time zone not null
)
    external name 'udrcpp_example!gen_dates2'
    engine udr;
***/
FB_UDR_BEGIN_PROCEDURE(gen_dates2)
	FB_UDR_MESSAGE(InMessage,
		(FB_TIMESTAMP_TZ, start_date)
		(FB_INTEGER, n_days)
	);

	FB_UDR_MESSAGE(OutMessage,
		(FB_TIMESTAMP_TZ, o_date)
	);

	FB_UDR_EXECUTE_PROCEDURE
	{
		out->o_dateNull = FB_FALSE;
		out->o_date = in->start_date;
		out->o_date.utcTimestamp.date--;
		counter = in->n_days;
	}

	FB_UDR_FETCH_PROCEDURE
	{
		out->o_date.utcTimestamp.date++;
		return counter-- > 0;
	}

	ISC_LONG counter;
FB_UDR_END_PROCEDURE

