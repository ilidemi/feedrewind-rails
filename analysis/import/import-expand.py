import sqlite3

links = []
with open("doc/expand.txt") as expand_f:
    for line in expand_f:
        line = line.strip()
        if len(line) == 0:
            break
        if not line.startswith("http"):
            continue
        url_comment = line.split(" -- ")
        if len(url_comment) == 2:
            links.append(tuple(url_comment))
        elif len(url_comment) == 1:
            links.append((url_comment[0], None))
        else:
            raise "Couldn't parse comment"
print(links)

db = sqlite3.connect("blogs.db")
cursor = db.cursor()

cursor.execute("delete from start_links")
print(f'{cursor.rowcount} rows deleted')

cursor.executemany("insert into start_links (url, comment, source_id) values (?, ?, 1)", links)
print(f'{cursor.rowcount} rows inserted')

cursor.execute("select count(*) from start_links")
print(cursor.fetchall())

db.commit()
db.close()
