# Messaging Protocol

0. Messages are represented on the wire using a Protocol Buffer structure.

    ```protobuf
    syntax = "proto2";
    package Aquae.Messaging;
    option java_package           = "uk.gov.Aquae.ProtocolBuffers";
    option java_outer_classname   = "Messaging";
    option java_multiple_files    = false;
    option java_string_check_utf8 = true;
    option java_generic_services  = false;
    ```

## Protocol

The Aquae Messaging Protocol consists of messages sent back and forth. It is not strictly a request/response style protocol. For now it is client server: a server listens for connections and a client opens a connection. When the converstaion is over, if neither peer closes the connection, it can be reused but the roles of the client and the server may not change.

This document outlines a number of Protocol Buffer Messages. Ones called `*Request` are suitable for a client to send to a server. Ones called `*Response` are suitable for a server to send back to a client. The server does not always have to have received a Request in order to be able to send a Response: unsolicited Responses are allowed and the client must handle them. All other Protocol Buffer Messages are definitions of domain level objects which are used by the Request/Response messages.

The server and client both need to implement a state machine. Not all Request or Response messages are appropriate in every state. If a server or a client sends an unexpected or inappropriate message, the receiving side should reply with a MessagingError message and close the connection. The recieving peer should log the Error and discard the associated connection and state, propagating the error condition to both upstream and downstream peers that are part of the Aquae transaction.

TODO: This should probably be signed so that intermediate nodes can't cause too much trouble and result in a split-brain view of an Aquae transaction.

TODO:
	patch for messagingerror enum in immediate-next
		and review of all other messages in the transport enum

  ```protobuf
  message MessagingError {
    optional string origin = 1; // Node name of the originating node.
    optional string reason = 2; // Human readable explanation of the error condition.
  }
  ```

## Querying

0. When a node wishes to make a query, it looks up the query in the metadata file and examines the available `Choices` for the query. TODO: who looks at the meteadata? Is it the first node within the Aquae network or is it another client library that is not in the metadata? E.g. there is a random webserver not part of the network communicating with a trusted Aquae node, who looks at the metadata here?

    1. The node should, where possible, expose these `choice`s to the user.

1. When a node has decided from the available `Choice`s, it creates a query plan using the metadata file according to the following algorithm.

    0. Start with a empty set of nodes which require the subject's identity (the "identity set").
    1. The node looks up which node can directly answer the question it wants answered (the "answering node") by examining the `ImplementingNodes`.

        1. If multiple nodes can answer the query, the node should load balance it's requests between all the nodes in the set. TODO: load balancing is messy. Can we exclude this from the MVP and just say each query must come from a specific node? Or: actually work out what problems this will cause and mitigate them.

    2. If the chosen node has a `MatchingSpec` requirement, the answering node is added to the identity set.
    3. The node looks up which subsequent questions must be answered to formulate the answer by examining the `requiredQuery` fields.
    4. Steps 1-3 are repeated until the query has been fully resolved and there are no further required queries. (It is up to the implementation to detect and prevent infinite loops but a correct parse of the Metadata will ensure this.) The node now has a set of nodes which will require the subject identity. TODO: need to resolve the `Choice`s of the lower level questions too. How do we present these to the user?
    5. The node looks up the matching requirement entries for the identity set nodes and computes any fields marked as `disambiguating` that are shared by two or more nodes. The node must submit these fields to all matching nodess that support them to ensure matching consistency (these fields are then considered `required`).
    6. The node then has both the fields required and fields that may subsequently be used for disambiguation or confidence-building for matching (the "match target").

2. The node collects the data required by the identity set nodes. Matching node must match using all fields that are sent, even if it doesn't think it requires them.

    0. TODO: nodes should receive the mininum amount of data required to do their job. When a node operates, it should use all the data it was given to verify as much correctness as possible.
    1. It is up to the node to decide what user interface is used and which fields are asked up front. The required fields are the minimum set, but the node may ask for all of the disambiguating fields too.

3. Having received match target data, the node submits the match target along with a list of identity set nodes to an Identity Bridge with which it has a DSA in the scope ???of the query it wishes to perform???. The identity bridge verifies (what does this mean? just verifies the requested query and resulting id attributes? or verifies that the identity is a real one?), encrypts and signs the identity for each matching node in the identity set. TODO: does the match target data come from the initiating node or the bridge in the Verify case? TODO: could/should the IdB run the UI for collection of data? We need to just give the matching node the initiating node identity and then rely on LOGGING to bust them if they are abused. But uh oh, killer question: **how does the audit server know that the matching node has lied? can we use canary queries for this?**

  ```protobuf
  message IdentitySignRequest {
    optional PersonIdentity subject_identity = 1;
    // TODO: also need to send the query that we want to run. Then identity bridge verifies.
    repeated string identity_set_nodes = 2;
  }

  message PersonIdentity {
    optional string surname = 1;
    optional string postcode = 2;
    optional int32 birth_year = 3;
    optional string initials = 4; // Initials in little endian Western order
    optional string house_number = 6;
    optional string date_of_birth = 7; // A date using our profile of RFC-3339 with hour, minute, seconds and portions of the second set to zero.
  }

  message AgentIdentity {
    // TODO: identity of an agent/client
  }

  message ServiceIdentity {
    // TODO: identity of the service making the request
  }

  message SignedIdentity { // is this the IdentitySignResponse?
    // TODO: unecrpyted container containing Redactable<T> fields
    // ID bridge cannot leave fields empty -> all are required
  }
  ```

4. The node creates a `Bindings` message, which links a `QueryPlan` with some signed identity data, and submits it to a consent service listed in the metadata file. The consent service signs the `Bindings` if its conditions are met or a `BadQueryResponse` if not. The query servers then satisfy themselves that the query being asked of them makes sense within the context of those `Bindings`.

    1. The consent service checks that the query is allowed to be asked for this subject now. How it does this is implementation-dependent, but a scheme which asks the subject for their permission or requires an agent to assert they have gained permission is the intention. TODO more?

    ```protobuf
    /* The pattern for signed messages is:
    message Signed<T> {
      optional T payload = 1;
      optional bytes signature = 2;
    }
    */

    ```

A `QueryPlan` is the name of the Query to answer and the Required Queries from the `Choice` that was chosen by the user for that Query.
If the Query has no `Choice`s to choose from then `required_query` is omitted.
TODO: This structure should be redactable.

We don't currently provide any support for the following things:

* Multiple implementing nodes for a query.
  We assume that all implementations are equivalent.

* Clustered nodes.
  We assume that all implementating nodes share a strongly consistent view of which Querys the others have run such that replay attacks are not possible.

* Multiple matching requirements for an implementing node for a query.
  When checking identity attributes (from PersonIdentity), if the consent service calculates that there is more information exposed than required or allowed by the matching requirements, then it should raise an error and refuse to sign the `Bindings`.

* Redacting parts of the query plan that the next hop node does not need to see.
  All nodes involved in the query are allowed to see the entire `QueryPlan` before and after them.

We require that implementing nodes keep track of transaction-ids, query-ids and nOnce such that each node in the `QueryPlan` for a given set of `Bindings` is never allowed to execute more than once.
Having answered a query, we do not currently require implementing nodes to be able to provide a cached answer in the event that an upstream node fails and subsequently requires to know the result of a Query that it was already given.

```protobuf
message QueryPlan {
  optional string    query_name     = 1;
  optional string    node_name      = 2;
  repeated QueryPlan required_query = 3;
}

```

A top-level query is answered by a transaction that answers it and all the dependent queries.
The work required of a transaction is described by binding a bunch of information together as set out below.
The `Bindings` are the description that the consent server signs.
The transaction-id is the digest of the `Bindings`. TODO: algorithm.

```protobuf
    message Bindings {
      optional bytes nOnce = 2; // Monotonically increasing value set by CS
      optional string scope = 9;
      optional SignedIdentity subjectIdentity = 3;
      optional PersonIdentity delegateIdentity = 4;
      optional AgentIdentity agentIdentity = 5;
      optional ServiceIdentity serviceIdentity = 6;
      optional QueryPlan plan = 8;
    }

    message SignedBindings {
      optional Bindings bindings = 1;
      optional bytes signature = 2;
    }

    // A Query is the query from the plan that is actually being asked together with its parameters.
    // query_id is the postorder index of the query in the query plan.
    message PrepareQuery {
      optional SignedBindings bindings = 1;
      optional bytes query_id = 2;
    }

    /* The pattern for redactable data structures is:
    message Redactable<T> {
      message RealValue {
        optional int salt = 1;
        optional T value = 2;
      }

      message EncryptedValue {
        optional bytes hash = 1;
        optional bytes blob = 2;
      }

      oneof {
        optional bytes hash = 1;
        optional RealValue value = 2;
        optional EncryptedValue encrypted = 3;
      }
    }
    */

    /* The pattern for redactable containers is:
    message RedactableContainer<T> {
      optional T message = 1;
      optional bytes rootHash = 2;
      optional bytes signatureOfHash = 3;
      optional map<string, bytes> nodeKeys = 4;
    }
    */
```

5. The sending node sends a `PrepareQuery` message to the first hop node.

    1. The sending node should redact the identity fields that are optional using the object hashing method TODO: what is the object hashing method. c.f. Ben Laurie who is well known.

   The receiving node checks the query is valid using it's metadata file. If it is invalid, it returns a `BadQuery` response. Receiving nodes should check that:

    0. The metadata versions are the same
    1. It can answer the query
        1. The node uses the `query_id` to find the Query that it is being asked to execute in the `QueryPlan`.
        2. The node finds the `QuerySpec` named in the `QueryPlan` in its Metadata.
        3. The node checks that the `required_query` list in the `QueryPlan` satisfies at least one `Choice` for the `QuerySpec` in the Metadata.
    2. The sending node (service) has authorization to ask that query (by checking the permissions/DSA) TODO: work out how to do same department permissions vs cross-department DSAs. "Smart nodes" e.g. proxies need permissions that are not listed in the metadata, pairs of nodes in metadata can use DSAs. At this stage the receiving node just checks that there is a DSA in scope that allows the sending node to pose this Query at all. In later stages we will check that the Query arguments / inputs also satisfy the DSA.
    3. The query is allowed to be run for this subject (by checking the appropriate consent server authorisation)
    4. No checks are made on the agent and delegate identities (this is handled by the consent server)
    6. The identity has been encrypted for the all the nodes that will need it (and not more)
    7. The identity contains all the fields required and shared between all of the nodes (as above)
    8. The transaction-id (the digest of the `Scope` object, not including the signature) has not been used before.

    ```protobuf
    message BadQueryResponse {
      enum Reason {
        STALE_METADATA = 0;
        CANNOT_ANSWER_QUERY = 1;
        SERVICE_UNAUTHORIZED = 2;
        NO_CONSENT_TOKEN = 3;
        AGENT_UNAUTHORIZED = 4;
        DELEGATE_UNAUTHORIZED = 5;
        MISSING_IDENTITY = 6;
        IDENTITY_TOO_OPEN = 7;
        MISSING_IDENTITY_FIELDS = 8;
      } // TODO: NCSC: how detailed is this in non-debug?

      optional bytes query_id = 1;
      optional Reason reason = 2;
    }
    ```

    If the `PrepareQuery` message is successful, the receiving node should proceed with the following steps. At this stage it is not necessary to reply to the sending node.

6. The receiving node starts preparing the query.

    1. The node constructs and sends `PrepareQuery` messages for each of the `required_query` entries from the `QueryPlan`. i.e. it conducts Step 5 for all the `required_query` entries, sending the messages to the next hop node.

        1. The `query_id` is defined by whatever information it needs from the next node.
        2. The `Bindings` are copied from the running query.

    3. If the metadata indicates that the node would be required to set up a match in order to answer the Query then it decrypts and attempts to match the `subjectIdentity` to it's database. This process is implementation-dependent.

    ```protobuf
    message QueryResponse {
      optional bytes query_id = 1;
      oneof result {
        MoreIdentityResponse more_identity_response = 3;
        MatchCompleteResponse match_complete_response = 4;
      }
    }
    ```

    All of the responses to a query are wrapped in a `MatchingResponse`.

      1. If the node decides it wants more information to disambiguate or build confidence in the match, it should send a `MoreIdentityResponse` encrypted with the session key and containing details of the fields required.

      ```protobuf
      message MoreIdentityResponse {
        message IdentityFields {
          repeated string fields = 1;
        }

        optional bytes encryptedIdentityFields = 1;
      } // TODO: encryption
      ```

      2. If the node decides it has finished matching and it is ready to proceed (either because it has a high-confidence single result, or because it cannot match the identity), it must send a `MatchCompleteResponse`.

      ```protobuf
      message MatchCompleteResponse {
	      optional bytes query_id = 1;
      } // TODO: Signing
      ```

      TODO: `MatchCompleteResponse` is sent when a matching node has identified zero or one records. However, what happens when it has consumed all the identity data and cannot identify a single record? Will it still send `MoreIdentityResponse` when it knows that it has used up all the redacted data? Whether or not this lack of match is a problem depends on the business logic of the actual question. Who decides whether to proceed with the next stage and how do they signal it?

    Servers that do not do matching do not need to generate a `MatchCompleteResponse`.

    Intermediate servers must pass through the encrypted responses to the origin node.

    Servers that do not do matching MUST ensure that all MatchCompleteRepsonses from their downstream nodes have finished passing to the origin node in a timely fashion after having receieved `MatchCompleteResponse`s from all their downstream nodes.

7. If any of the nodes return a `MoreIdentityResponse`, the initiating node must resubmit the `PrepareQuery` message with unredacted identity fields.

    When this occurs nodes may be keeping track of intermediate state. They are allowed to reuse this state but the message flow between them must proceed as if from Step 5 but with the extra identity data present.

    1. The identity message must contain exactly the fields it did previously along with every field that was additionally requested by one or more nodes.
    2. The same set of fields must be sent to each node.

8. When the origin node has received `MatchCompleteResponse`s from all of the identity nodes, it sends a `SecondWhistle` message along the query path to tell the query servers to begin executing the query logic against the data from the matched records. Once the `SecondWhistle` has been processed, the node can finalise the transaction and clear resources - no further messages for this `query_id` are permitted.

    ```protobuf
    message SecondWhistle {
      optional bytes query_id = 1;
      //repeated Param inputs   = 3; //TODO: way of expressing this TBC
      // TODO: how do we ensure this comes from the initiating node??
    }
    ```

8. The nodes on the query path execute the query logic.

    1. If the node requires data from another node, it creates its own `SecondWhistle` message, sends it to that node and awaits the `QueryAnswer`. It is up to the node when and if it actually forwards the `SecondWhistle` message however, it MUST NOT send the `SecondWhistle` message if it does not actually need to use the data to execute the query logic.

        ```protobuf
        message QueryAnswer {
          optional bytes query_id = 1;
          oneof result {
            ValueResponse value = 2;
            ErrorResponse error = 3;
          }
        }
        ```

    2. If the node has all the data required to run a query (either as data from a database it has access to or from responses from other nodes), it transforms the result according to the required query, and then returns a `ValueResponse`.

        ```protobuf
        message ValueResponse {
          // TODO: how do we represent this?
          // TODO: attribute standards fields, e.g. currency, expiry
        }
        ```

    3. If the node fails to run the query, it returns an `ErrorResponse`.

        ```protobuf
        message ErrorResponse {
          // TODO
        }
        ```

    4. If it finishes a query and has not forwarded the `SecondWhilstle` message, it must instead send a `Finish` message to allow the subsequent nodes to clear resources.

        ```protobuf
        message Finish {
          optional bytes query_id = 1;
        }
        ```

9. That's it.

