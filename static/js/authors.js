async function list_authors(search,banned,page,page_size) {
    const uri = "/api/authors/?"+new URLSearchParams({
        "search": search,
        "banned": banned,
        "page": page,
        "page-size": page_size
    })
    const response = await fetch(uri, {
        method: "GET"
    })
    return await response.json()
}

const searchbar = u("#search")
const banned_toggle = u("#banned-toggle")
const search_button = u("#search-button")
let page = 1;
let page_count = 0;
const page_size = 3;
const authors_frame = u("#frame")
const author_template = u("#author-template")
const pagenav_frame = u(".page-nav")
const pagelink_template = u("#pagelink-template")
async function update(p) {
    page = p || page
    const data = await list_authors(searchbar.first()?.value || '',banned_toggle.first()?.checked || false,page,page_size)
    page_count = data["page-count"]
    authors = data["authors"]
    authors_frame.empty()
    authors.map(
        (a) => {
            const node = author_template.first().content.cloneNode(true)
            const anchor = u("a",node).first()
            anchor.id=a.id
            anchor.href="/users/"+a.id.toString()
            u(".author-avatar",node).first().src=a.avatar
            u(".author-name",node).text(a.name)
            u(".author-sample",node).first().src=a.extra.thumbnail
            authors_frame.append(node)
        }
    )
    update_pagenav()
}

function update_pagenav() {
    const push_page = (i) => {
        pagenav_frame.nodes.forEach((x) => {
            const active = i==page;
            const node = pagelink_template.first().content.cloneNode(true)
            const unode = u("a",node)
            unode.text(i.toString())
            if (active) {
                unode.addClass('active')
            }
            u(x).append(unode)
            unode.handle('click',(_) => {
                update(i)
            })
        })
    }
    pagenav_frame.empty()
    push_page(1)
    if (page-3>1) {
        pagenav_frame.append('<span>...</span>')
    }
    for (let i = Math.max(2,page-3); i <= Math.min(page+3,page_count); i++) {
        push_page(i)
    }
    if (page+3<page_count) {
        pagenav_frame.append('<span>...</span>')
        push_page(page_count)
    }
}

search_button.handle('click',(_) => update(1))
update(1)