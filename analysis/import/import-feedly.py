import sqlite3

links = []
with open("import/feedly.txt") as feedly_f:
    for line in feedly_f:
        line = line.strip()
        if len(line) == 0:
            break
        if not line.startswith("http"):
            continue
        links.append((line,))
print(links)

db = sqlite3.connect("blogs.db")
cursor = db.cursor()

cursor.execute("delete from start_links where source_id = 2")
print(f'{cursor.rowcount} rows deleted')

cursor.executemany("insert into start_links (url, source_id) values (?, 2)", links)
print(f'{cursor.rowcount} rows inserted')

cursor.execute("select count(*) from start_links")
print(cursor.fetchall())

db.commit()
db.close()
