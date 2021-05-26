from bs4 import BeautifulSoup
import os

active_count = inactive_count = 0
long_count = short_count = 0

url_comments = []
for filename in os.listdir('users'):
    with open(f'users/{filename}', encoding='utf-8') as f:
        content = f.read()
        html = BeautifulSoup(content, 'html.parser')
        table = html.find('table')
        rows = list(filter(lambda c: c.name == 'tr' and 'class' not in c.attrs, table.children))[1:]
        for row in rows:
            rss = row.findChild('td').findChild('a').attrs['href']
            posts_count = int(row.findChild('td').span.text[1:-7])
            status = row.findChildren('td')[1].span.text
            
            comments = []
            if posts_count < 10:
                short_count += 1
                comments.append(f'{posts_count} posts')
            else:
                long_count += 1
            if status == 'Active':
                active_count += 1
            else:
                inactive_count += 1
                comments.append(status)
            comment = ', '.join(comments) if len(comments) > 0 else None
            url_comments.append((rss, comment))

print(len(url_comments))
print('long count:', long_count, 'short count:', short_count)
print('active count:', active_count, 'inactive count:', inactive_count)

with open('rss.csv', 'w', encoding='utf-8') as rss:
    for url_comment in url_comments:
        comment_str = '' if url_comment[1] is None else url_comment[1]
        rss.write(f'{url_comment[0]};{comment_str}\n')
