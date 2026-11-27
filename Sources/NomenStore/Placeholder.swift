import GRDB
func _probe() throws { let q = try DatabaseQueue(); try q.write { try $0.execute(sql: "CREATE TABLE t(a)") } }
