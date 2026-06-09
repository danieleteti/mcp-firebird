# Time Zone support forward compatibility

In version 4.0, Firebird will support time zones.

Within this support will come an incompatibility with previous versions' `CURRENT_TIME` and `CURRENT_TIMESTAMP` expressions.

In v4, `CURRENT_TIME` and `CURRENT_TIMESTAMP` will respectively return expressions of data type `TIME WITH TIME ZONE` and `TIMESTAMP WITH TIME ZONE`.

To make your queries and database code compatible with future versions, from v3.0.4 you can instead use `LOCALTIME` and `LOCALTIMESTAMP`. In v2.5.9, v3.0.4 and next point releases, these `LOCAL*` expressions will work indenticaly to their correspondents `CURRENT_*` expressions.

In v4, `LOCAL*` expressions will continue to work identically as now, but the `CURRENT_*` expressions will change.

You should not start using `LOCALTIME` and `LOCALTIMESTAMP` if your database may be downgraded to a version without
that support (v2.5.8, v3.0.3), as the old versions will not recognize the new expressions.
