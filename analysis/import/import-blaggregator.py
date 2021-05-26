import sqlite3

url_comments = []
with open('import/blaggregator/links.csv') as f:
    for line in f:
        line = line.strip()
        url, comment = line.split(';')
        url_comments.append((url, comment))

db = sqlite3.connect("blogs.db")
cursor = db.cursor()

cursor.execute("delete from start_links where source_id = 3")
print(f'{cursor.rowcount} rows deleted')

cursor.executemany("insert into start_links (url, comment, source_id) values (?, ?, 3)", url_comments)
print(f'{cursor.rowcount} rows inserted')

cursor.execute("select count(*) from start_links group by source_id")
print(cursor.fetchall())

db.commit()
db.close()