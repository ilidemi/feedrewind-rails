window.localStorage
    .setItem('u', Array.from(
        new Set($$("img[data-author-id]")
            .map(i => i.attributes["data-author-id"].value)
            .concat((window.localStorage.getItem('u') || "")
                .split(";")
                .filter(s => s))
        )
    ).join(';'));
$$(".page-link").reverse()[0].click()

window.localStorage.getItem('u')

window.localStorage
    .setItem('rss',
        Array.from(document.getElementsByClassName('table')[0].tBodies[0].rows)
            .slice(1)
            .filter(row => row.cells[0].getElementsByTagName('a')[0])
            .map(row => row.cells[0].getElementsByTagName('a')[0].attributes['href'].value)
            .concat((window.localStorage.getItem('rss') || "").split(";").filter(s => s))
            .join(';'))

window.localStorage.getItem('rss')

