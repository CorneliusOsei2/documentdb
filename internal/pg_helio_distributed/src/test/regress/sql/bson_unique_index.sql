
SET search_path TO helio_core,helio_api,helio_api_catalog,helio_api_internal;

SET citus.next_shard_id TO 560000;
SET helio_api.next_collection_id TO 5600;
SET helio_api.next_collection_index_id TO 5600;

-- insert a document
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"1", "a": { "b": 1 } }', NULL);

-- Create a unique index on the collection.
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "a.b": 1 }, "name": "rumConstraint1", "unique": 1 }] }', true);
SELECT * FROM helio_distributed_test_helpers.get_collection_indexes('db', 'queryuniqueindex') ORDER BY collection_id, index_id;

-- insert a value that doesn't collide with the unique index.
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"2", "a": [ { "b": 2 }, { "b" : 3 }]}', NULL);

-- insert a value that has duplicate values that do not collide with other values.
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"3", "a": [ { "b": 4 }, { "b" : 4 }]}', NULL);

-- insert a value that has duplicate values that collide wtih other values.
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"4", "a": [ { "b": 5 }, { "b" : 3 }]}', NULL);
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"5", "a": { "b": [ 5, 3 ] } }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"6", "a": { "b": 3 } }', NULL);

-- valid scenarios again.
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"4", "a": [ { "b": 5 }, { "b" : 6 }]}', NULL);
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"5", "a": { "b": [ 7, 9 ] } }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"6", "a": { "b": 8 } }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"7", "a": { "b": true } }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"8", "a": { "b": "someValue" } }', NULL);

-- we can use the unique index for queries
BEGIN;
set local helio_api.forceUseIndexIfAvailable to on;
set local enable_seqscan TO off;
set local helio_api.forceRumIndexScantoBitmapHeapScan TO OFF;
EXPLAIN (COSTS OFF) SELECT document FROM helio_api.collection('db', 'queryuniqueindex') WHERE document @@ '{ "a.b": { "$gt": 5 } }';
ROLLBACK;

-- insert a document that does not have an a.b (should succeed)
SELECT helio_api.insert_one('db','queryuniqueindex','{"a": { "c": "someValue" } }', NULL);

-- insert another document that does not have an a.b (should fail)
SELECT helio_api.insert_one('db','queryuniqueindex','{"a": { "d": "someValue" } }', NULL);

-- insert another document that has a.b = null (Should fail)
SELECT helio_api.insert_one('db','queryuniqueindex','{"a": { "b": null } }', NULL);

-- insert a document that has constraint failure on _id
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id": "8", "a": { "b": 2055 } }', NULL);

-- drop the unique index.
CALL helio_api.drop_indexes('db', '{"dropIndexes": "queryuniqueindex", "index": ["rumConstraint1"]}');
SELECT * FROM helio_distributed_test_helpers.get_collection_indexes('db', 'queryuniqueindex') ORDER BY collection_id, index_id;

-- now we can violate the unique constraint
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"9", "a": { "b": 1 } }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"10", "a": { "b": [ 2, 1 ] } }', NULL);

-- create an index when the collection violates unique. Should fail.
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "a.b": 1 }, "name": "rumConstraint1", "unique": 1, "sparse": 1 }] }', true);

-- create a unique index with the same name ( should be fine since we dropped it )
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "c": 1 }, "name": "rumConstraint1", "unique": 1, "sparse": 1 }] }', true);
SELECT * FROM helio_distributed_test_helpers.get_collection_indexes('db', 'queryuniqueindex') ORDER BY collection_id, index_id;

-- since this is sparse, we can create several documents without "c" on it.
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"11", "d": "someValue" }', NULL);

-- insert another document that does not have an c (should succeed)
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"12", "e" : true }', NULL);

-- insert another document that has a.b = null (Should succeed)
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"13", "c": null }', NULL);

-- however, inserting 'c' again should fail.
SELECT helio_api.insert_one('db','queryuniqueindex','{"_id":"14", "c": null }', NULL);

-- drop the unique index by key.
CALL helio_api.drop_indexes('db', '{"dropIndexes": "queryuniqueindex", "index": {"c": 1} }');
SELECT * FROM helio_distributed_test_helpers.get_collection_indexes('db', 'queryuniqueindex') ORDER BY collection_id, index_id;

-- create unique index fails for wildcard.
SELECT helio_api_internal.create_indexes_non_concurrently('uniquedb', '{"createIndexes": "collection1", "indexes": [{"key": {"f.$**": 1}, "name": "my_idx3", "unique": 1.0}]}', true);
SELECT helio_api_internal.create_indexes_non_concurrently('uniquedb', '{"createIndexes": "collection1", "indexes": [{"key": {"$**": 1}, "wildcardProjection": { "f.g": 0 }, "name": "my_idx3", "unique": 1.0}]}', true);

-- test for sharded
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"1", "a": { "b": 1 }, "d": 1 }', NULL);
SELECT helio_api.shard_collection('db', 'queryuniqueindexsharded', '{ "d": "hashed" }', false);

-- Create a unique index on the collection.
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindexsharded", "indexes": [ { "key" : { "a.b": 1 }, "name": "rumConstraint1", "unique": 1 }] }', true);
SELECT * FROM helio_distributed_test_helpers.get_collection_indexes('db', 'queryuniqueindexsharded') ORDER BY collection_id, index_id;

-- valid scenarios:
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"2", "a": { "b": [ 2, 2] }, "d": 1 }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"3", "a": { "b": [ 3, 4 ] }, "d": 1 }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"4", "a": { "b": 5 }, "d": 1 }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"5", "a": { "c": 5 }, "d": 1 }', NULL);

-- now violate unique in shard key "d": 1 
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"6", "a": { "b": [ 3, 6 ] }, "d": 1 }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"7", "a": { "b": null }, "d": 1 }', NULL);

-- now insert something in a different shard - should not violate unique
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"8", "a": { "b": [ 3, 6 ] }, "d": 2 }', NULL);
SELECT helio_api.insert_one('db','queryuniqueindexsharded','{"_id":"9", "a": { "b": null }, "d": 2 }', NULL);

-- still can be used for query.
BEGIN;
set local helio_api.forceUseIndexIfAvailable to on;
set local enable_seqscan TO off;
EXPLAIN (COSTS OFF) SELECT document FROM helio_api.collection('db', 'queryuniqueindexsharded') WHERE document @@ '{ "a.b": { "$gt": 5 } }';
ROLLBACK;

-- create unique index with truncation

SELECT string_agg(md5(random()::text), '_') AS longstring1 FROM generate_series(1, 100) \gset
SELECT string_agg(md5(random()::text), '_') AS longstring2 FROM generate_series(1, 100) \gset
SELECT string_agg(md5(random()::text), '_') AS longstring3 FROM generate_series(1, 100) \gset
SELECT string_agg(md5(random()::text), '_') AS longstring4 FROM generate_series(1, 100) \gset

SELECT length(:'longstring1');

-- create with truncation allowed and the new op-class enabled
set helio_api.enable_large_unique_index_keys to on;

SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "e": 1 }, "name": "rumConstraint1", "unique": 1, "unique": 1, "sparse": 1 }] }', true);
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "e": 1, "f": 1 }, "name": "rumConstraint2", "unique": 1, "unique": 1, "sparse": 1 }] }', true);
\d helio_data.documents_5600

-- succeeds
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 1, "e": "%s", "f": 1 }', :'longstring1')::bson);

-- unique conflict
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 2, "e": [ "%s", "%s" ], "f": 1 }', :'longstring1', :'longstring2')::bson);

-- create with suffix post truncation - succeeds
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 3, "e": [ "%s-withsuffix", "%s" ], "f": 1 }', :'longstring1', :'longstring2')::bson);

-- this should also fail
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 4, "e": "%s-withsuffix", "f": 1 }', :'longstring1')::bson);

-- this will work.
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 5, "e": "%s-withsuffix", "f": 1 }', :'longstring2')::bson);

-- this will fail (suffix match of array and string).
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 6, "e": [ "%s", "%s-withsuffix" ], "f": 1 }', :'longstring3', :'longstring2')::bson);

-- test truncated elements with numeric types of the same/different equivalent value. 
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 7, "e": { "path1": "%s", "path2": 1.0 }, "f": 1 }', :'longstring3')::bson);
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 8, "e": { "path1": "%s", "path2": { "$numberDecimal": "1.0" }}, "f": 1 }', :'longstring3')::bson);
SELECT helio_api.insert_one('db', 'queryuniqueindex', FORMAT('{ "_id": 9, "e": { "path1": "%s", "path2": { "$numberDecimal": "1.01" }}, "f": 1 }', :'longstring3')::bson);

-- test composite sparse unique indexes: Should succeed since none of the documents have this path (sparse unique ignore)
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "g": 1, "h": 1 }, "name": "rumConstraint3", "unique": 1, "sparse": 1 }] }', true);

-- works
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "g": 5, "h": 5 }');

-- fails (unique cosntraint)
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "g": 5, "h": 5 }');

-- works
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "g": 5 }');

-- fails (unique constraint)
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "g": 5 }');

-- works
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "h": 5 }');

-- fails (unique constraint)
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "h": 5 }');

-- reset test data
set helio_api.enable_large_unique_index_keys to on;

DELETE FROM helio_data.documents_5600;
CALL helio_api.drop_indexes('db', '{ "dropIndexes": "queryuniqueindex", "index": [ "rumConstraint1", "rumConstraint2", "rumConstraint3" ] }');

\d helio_data.documents_5600

-- test unique sparse composite index
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "key1": 1, "key2": 1 }, "name": "constraint1", "unique": 1, "sparse": 1 }] }', true);

\d helio_data.documents_5600

-- should succeed and generate terms for all combinations on both arrays
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": [1, 2, 3], "key2": [4, 5, 6] }');

-- should fail due to terms permutation on both arrays
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": [1, 2, 3], "key2": [4, 5, 6] }');

SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 1, "key2": 4 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 1, "key2": 5 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 1, "key2": 6 }');

SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 2, "key2": 4 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 2, "key2": 5 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 2, "key2": 6 }');

SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 3, "key2": 4 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 3, "key2": 5 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 3, "key2": 6 }');

-- now test array permutations with missing key
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": [1, 2, 3, 4, 5] }');

-- should fail with undefined permutations on missing key
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 2 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 3 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 4 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 5 }');

-- should succeed with null permutations on missing key (sparse)
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 1, "key2": null }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 2, "key2": null }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 3, "key2": null }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 4, "key2": null }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 5, "key2": null }');

-- should succeed due to new combinations
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 6 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 6, "key2": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 6, "key2": 2 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 6, "key2": 3 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 6, "key2": 4 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key2": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key2": 2 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key2": 3 }');

-- should work because doesn't fall in unique constraint
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key3": [1, 2] }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key3": [1, 2] }');

-- reset data
set helio_api.enable_large_unique_index_keys to on;

DELETE FROM helio_data.documents_5600;
CALL helio_api.drop_indexes('db', '{ "dropIndexes": "queryuniqueindex", "index": [ "constraint1" ] }');

\d helio_data.documents_5600

-- now test composite not-sparse unique index
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "key1": 1, "key2": 1 }, "name": "constraint1", "unique": true, "sparse": false }] }', true);

\d helio_data.documents_5600

-- test array permutations with missing key
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": [1, 2, 3, 4, 5] }');

-- should fail with undefined permutations on missing key
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 2 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 3 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 4 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 5 }');

-- should fail with null permutations on missing key (non-sparse)
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 1, "key2": null }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 2, "key2": null }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 3, "key2": null }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 4, "key2": null }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "key1": 5, "key2": null }');

-- reset data
set helio_api.enable_large_unique_index_keys to on;

DELETE FROM helio_data.documents_5600;
CALL helio_api.drop_indexes('db', '{ "dropIndexes": "queryuniqueindex", "index": [ "constraint1" ] }');

\d helio_data.documents_5600

-- now test composite not-sparse unique index
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "a": 1, "b": 1, "c": 1 }, "name": "constraint1", "unique": true, "sparse": true }] }', true);

\d helio_data.documents_5600

-- should work
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1, "b": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1, "c": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "b": 1, "c": 1 }');

-- repeated documents won't matter because  they don't fall in the index (sparse)
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "z": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "z": 1 }');

-- should fail
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1, "b": 1 }');

-- reset data
set helio_api.enable_large_unique_index_keys to on;

DELETE FROM helio_data.documents_5600;
CALL helio_api.drop_indexes('db', '{ "dropIndexes": "queryuniqueindex", "index": [ "constraint1" ] }');

\d helio_data.documents_5600

-- now test composite not-sparse unique index
SELECT helio_api_internal.create_indexes_non_concurrently('db', '{ "createIndexes": "queryuniqueindex", "indexes": [ { "key" : { "a": 1, "b": 1, "c": 1 }, "name": "constraint1", "unique": true, "sparse": false }] }', true);

\d helio_data.documents_5600

-- should work
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1, "b": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1, "c": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "b": 1, "c": 1 }');

-- repeated documents will matter because they fall in the index (non-sparse)
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "z": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "z": 1 }');

-- should fail
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1 }');
SELECT helio_api.insert_one('db', 'queryuniqueindex', '{ "a": 1, "b": 1 }');

-- test new op class (generate_unique_shard_document) for composite sparse indexes

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": 1, "key2": "b" }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, true);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": 1, "key3": "b" }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, true);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": [1, 2, 3, 4, 5] }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, true);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": [1, 2, 3, 4, 5], "key2": 3 }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, true);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": [1, 2, 3, 4, 5], "key2": ["a"] }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, true);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": "abobora", "key2": ["jabuticaba"] }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, true);

SELECT helio_api_internal.generate_unique_shard_document('{ "key3": "b" }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, true);

-- test new op class (generate_unique_shard_document) for composite not sparse indexes

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": 1, "key2": "b" }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, false);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": 1, "key3": "b" }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, false);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": [1, 2, 3, 4, 5] }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, false);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": [1, 2, 3, 4, 5], "key2": 3 }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, false);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": [1, 2, 3, 4, 5], "key2": ["a"] }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, false);

SELECT helio_api_internal.generate_unique_shard_document('{ "key1": "abobora", "key2": ["jabuticaba"] }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, false);

SELECT helio_api_internal.generate_unique_shard_document('{ "key3": "b" }', 1, '{ "key1" : { "$numberInt" : "1" }, "key2" : { "$numberInt" : "1" } }'::bson, false);