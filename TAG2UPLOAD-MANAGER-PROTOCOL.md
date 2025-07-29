# Protocol between the tag2upload Manager and the Oracle.

## Initiation and lifecycle

The Oracle initiates the connection.
The transport is `ssh manager nc`:
ie, the Manager will be listening on a local socket.
(There will be an ssh restricted command.)

In principle,
the Oracle might make multiple connections,
if it has multiple worker processes.
In that case, each worker has one connection.

The ssh connection will use "protocol keepalives",
so that the Manager will (eventually) detect a failure.

## Protocol 

### Basic principles; notation

The protocol is line-based.
Lines are terminated by newlines.
Extraneous whitespace is a protocol violation.

We see things from the Oracle's point of view.  
`<` is from Manager to Oracle.

### Initial exchange

```
$ ssh manager nc -U /srv/socket
< t2u-manager-ready
> t2u-oracle-version 4
> worker-id WORKER-ID FIDELITY
```

If there are multiple protocol versions,
the Oracle gets to choose its preferred one.

This document describes version `4`.
In `3` and earlier, `PUTATIVE-PACKAGE` is omitted from the `job` message.
In `2` and earlier, `FIDELITY` is omitted from the `worker-id` message.

(The protocol version could be on the command line,
but that entangles it with the ssh restricted command.)

The WORKER-ID must consist of ASCII alphanumerics,
commas, hyphens, and dots, and must start with an alphanumeric.
It is used by the manager for reporting,
including in public-facing status reports.
If the Oracle manages multiple Builders,
it should make multiple connections to the Oracle,
one for each Builder.
(The `worker-id` message is mandatory.)

`FIDELITY` is one of the fixed strings `testing` or `production`,
according to the Oracle's self-determination of its own status.
The Manager will not give out jobs to to a non-`production` Oracle,
unless it explicitly so instructed by its administrator.

### Readiness

The Oracle should then wait, indefinitely,
for a job to be available.

During this time,
the Manager will periodically poll the Oracle for readiness:

```
< ayt
> ack
```

This allows the Manager to detect a dead Oracle connection.

Before responding with `ack`, the Oracle should attempt to discover
any reasons why the processing of a source package is bound to fail.
In particular, ideally, the Oracle would check that:
 * it can contact its Builder;
 * the build environment (the autopkgtest testbed) is `open`;
 * the build environment is accessible (commands can be run in it);
 * the signing key it intends to use is available.

The Oracle need not check anything visible to the Manager.
For example, the Oracle need not check availability of dgit-reposs,
the ftpmaster upload queue, or input git repository servers (eg salsa).

### Job

```
< job JOB-ID PUTATIVE-PACKAGE URL
< data-block NBYTES
< [NBYTES bytes of data for the tag (no newline)]
< data-end
```

JOB-ID is the "job id" assigned by the Manager,
and displayed in the Manager's reporting web pages etc.
The Oracle should use it only for reporting.
It has the same syntax as BUILDER-ID.

PUTATIVE-PACKAGE is the source package name.
It is derived from the Manager's parse of the tag data,
so should be used for reporting only.
The Oracle must reparse the tag for itself after verifying the signature.

URL is the git URL for the repository where the tag exists.
It is guaranteed to consist of ASCII graphic characters.

The NBYTES of data are precisely the git tag object,
as output by `git cat-file tag`.

This protocol is identical to the `dgit rpush` file transfer protocol,
except that the Manager guarantees to put the whole tag
in one data block.
(So there will be only one `data-block`.)

After receiving a job, the Oracle must produce an outcome.
If it doesn't, the job (perhaps, that package version)
is irrecoverable.

### Outcome

```
> message MESSAGE
> uploaded
```

or

```
> message MESSAGE
> irrecoverable
```

MESSAGE is UTF-8 text, possibly containing whitespace,
up to the newline.

The manager will log it,
and display it publicly in its status reports.

### Conclusion

After sending the outcome,
the Oracle should either close the connection,
or retain it and wait for further jobs.

### Protocol violations, reporting

Either side may send this message, at any time
(except in the middle of data blocks)
if it considers that its peer has violated the protocol:

```
> protocol-violation MESSAGE
< protocol-violation MESSAGE
```

The complaining side should then close the connection.

The complained-at side should report the error somewhere,
and will ideally display it in user-facing output
such as status web pages or emails.
It should also then close the connection.

The complaining side that sends `protocol-violation`
should *also* report or log the error as appropriate.

### Connection failures - handling by Oracle

If the connection is dropped,
or a connection attempt is unsuccessful,
the Oracle should retry with a delay.

### Connection failures - handling by Manager

If the connection fails (or the protocol is violated)
after `job` and before the outcome,
the job is treated as irrecoverable.

To Manager always does an `ayt` check
immediately before issuing a job,
to minimise the opportunity for jobs to be lost
simply because of a broken connection.

(The rest of the time the Manager doesn't care about connection failure.)

### Error recovery and retrying jobs

In this version of the protocol there is no way to retry a failed job.

For example, if the Builder is unable to clone the repo,
the tag is irrecoverable and a new version number must be used.

If this turns out to be annoying in practice,
we should have the Oracle ask the Manager for confirmation
just before it first makes a signature,
as that is the point of no return.
