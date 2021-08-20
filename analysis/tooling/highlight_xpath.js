// On https://journal.stuffwithstuff.com/archive/

document.body.scrollIntoView();
$x("/html[1]/body[1]/div[1]/article[1]/div[*]/a[1]").forEach(a => {
    let boundingRect = a.getBoundingClientRect();
    let overlay = document.createElement("a");
    overlay.style.position = "absolute";
    overlay.style.top = `${boundingRect.y}px`;
    overlay.style.left = `${boundingRect.x}px`;
    overlay.style.width = `${boundingRect.width}px`;
    overlay.style.height = `${boundingRect.height}px`;
    overlay.style.backgroundColor = "#FFFF0080";
    overlay.href = a.href;
    document.body.appendChild(overlay);
});