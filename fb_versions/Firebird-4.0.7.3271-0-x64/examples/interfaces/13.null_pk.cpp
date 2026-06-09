/*
 *	PROGRAM:	Object oriented API samples.
 *	MODULE:		13.null_pk.cpp
 *	DESCRIPTION:	Changing metadata, passed from DB engine, and using modified
 *					copy later. Useful for changing nullability or coercing datatype.
 *					In this sample we insert NULLs in all columns.
 *
 *					Example for the following interfaces:
 *					IMessageMetadata - describe input and output data format
 *					IMetadataBuilder - tool to modify/create metadata
 *
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
 *					Alex Peshkov, 2013, 2020
 */

#include "ifaceExamples.h"

static IMaster* master = fb_get_master_interface();

int main()
{
	int rc = 0;

	// set default password if none specified in environment
	setenv("ISC_USER", "sysdba", 0);
	setenv("ISC_PASSWORD", "masterkey", 0);

	// status vector and main dispatcher
	ThrowStatusWrapper status(master->getStatus());
	IProvider* prov = master->getDispatcher();

	// declare pointers to required interfaces
	IAttachment* att = NULL;
	ITransaction* tra = NULL;

	// Interface executes prepared SQL statement
	IStatement* stmt = NULL;

	// Interfaces provides access to format of data in messages
	IMessageMetadata* meta = NULL;

	// Interface makes it possible to change format of data or define it yourself
	IMetadataBuilder* builder = NULL;

	const char* sqlStr =
	    "Insert into COUNTRY values(?, ?)";

	try
	{
		// attach employee db
		att = prov->attachDatabase(&status, "employee", 0, NULL);

		// start transaction
		tra = att->startTransaction(&status, 0, NULL);

		// prepare statement
		stmt = att->prepare(&status, tra, 0, sqlStr, SAMPLES_DIALECT, 0);

		// build metadata
		meta = stmt->getInputMetadata(&status);
		builder = meta->getBuilder(&status);

		// set nullability on fields
		for (unsigned n = 0; n < meta->getCount(&status); ++n)
		{
			unsigned t = meta->getType(&status, n);
			builder->setType(&status, n, t | 1);
		}

		// IMetadata should be ready
		meta->release();
		meta = NULL;
		meta = builder->getMetadata(&status);

		// no need in builder any more
		builder->release();
		builder = NULL;

		// allocate buffer on stack
		char buffer[256];
		unsigned len = meta->getMessageLength(&status);
		if (len > sizeof(buffer))
		{
			throw "Input message length too big - can't continue";
		}

		// all null
		for (unsigned n = 0; n < meta->getCount(&status); ++n)
		{
 			short* flag = (short*)&buffer[meta->getNullOffset(&status, n)];
	 		*flag = -1;
	 		// setting value for NULL field makes no sense - skip it
	 	}

		// this should throw - passing NULLs to not-NULL columns
		// can work only with something like before insert trigger
	    stmt->execute(&status, tra, meta, buffer, NULL, NULL);

		// close interfaces
		stmt->free(&status);
		stmt = NULL;

		meta->release();
		meta = NULL;

		tra->rollback(&status);
		tra = NULL;

		att->detach(&status);
		att = NULL;
	}
	catch (const FbException& error)
	{
		// handle error
		rc = 1;

		char buf[256];
		master->getUtilInterface()->formatStatus(buf, sizeof(buf), error.getStatus());
		fprintf(stderr, "%s\n", buf);
	}

	// release interfaces after error caught
	if (builder)
		builder->release();
	if (meta)
		meta->release();
	if (stmt)
		stmt->release();
	if (tra)
		tra->release();
	if (att)
		att->release();

	prov->release();
	status.dispose();

	return rc;
}

