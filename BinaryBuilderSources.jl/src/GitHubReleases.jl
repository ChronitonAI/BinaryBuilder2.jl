using Downloads, JSON
using BinaryBuilderGitUtils: url_access_token

"""
    github_release_download(url)

If `url` is the download URL of a file attached to a GitHub release, i.e.
`https://github.com/<owner>/<repo>/releases/download/<tag>/<name>`, return the
`(owner, repo, tag, name)` it refers to, with `tag` and `name` percent-decoded.
Otherwise, return `nothing`.
"""
function github_release_download(url::AbstractString)
    m = match(r"^https://github\.com/([^/?#]+)/([^/?#]+)/releases/download/([^?#]+)/([^/?#]+)$", url)
    if m === nothing
        return nothing
    end
    owner, repo, tag, name = m.captures
    return (String(owner), String(repo), percent_decode(tag), percent_decode(name))
end

# Decode the `%XX` escapes of a URL component
function percent_decode(s::AbstractString)
    bytes = codeunits(s)
    out = UInt8[]
    i = 1
    while i <= length(bytes)
        if bytes[i] == UInt8('%') && i + 2 <= length(bytes) &&
           all(b -> isxdigit(Char(b)), bytes[i+1:i+2])
            push!(out, parse(UInt8, String(bytes[i+1:i+2]); base=16))
            i += 3
        else
            push!(out, bytes[i])
            i += 1
        end
    end
    return String(out)
end

# Percent-encode `s` for use as a single URL path segment (so `/` is escaped as well)
function percent_encode(s::AbstractString)
    io = IOBuffer()
    for b in codeunits(s)
        c = Char(b)
        if isascii(c) && (isletter(c) || isdigit(c) || c in "-._~")
            write(io, b)
        else
            print(io, '%', uppercase(string(b; base=16, pad=2)))
        end
    end
    return String(take!(io))
end

"""
    github_api_json(url)

GET `url` from the GitHub API and return the parsed JSON response.  The token configured
in `access_tokens` for the repository `url` points into, if any, is sent along.
"""
function github_api_json(url::AbstractString)
    headers = ["Accept" => "application/vnd.github+json"]
    token = url_access_token(url)
    if token !== nothing
        push!(headers, "Authorization" => "Bearer $(token)")
    end
    io = IOBuffer()
    Downloads.download(url, io; headers)
    return JSON.parse(String(take!(io)))
end

"""
    github_release_asset_url(owner, repo, tag, name; get_json = github_api_json)

Look up the file `name` attached to the GitHub release `tag` of `owner/repo` through the
GitHub API, and return its API URL
(`https://api.github.com/repos/<owner>/<repo>/releases/assets/<id>`).  It serves the same
file as the release download URL does (see `download_headers()`), and it also works for
private repositories and where only the API is reachable.  `get_json(url)` performs the
API requests.  Throws an `ArgumentError` if the release has no such file.
"""
function github_release_asset_url(owner::AbstractString, repo::AbstractString,
                                  tag::AbstractString, name::AbstractString;
                                  get_json::Function = github_api_json)
    release = get_json("https://api.github.com/repos/$(owner)/$(repo)/releases/tags/$(percent_encode(tag))")
    assets = release["assets"]
    page = 0
    while true
        idx = findfirst(asset -> asset["name"] == name, assets)
        if idx !== nothing
            return String(assets[idx]["url"])
        end
        # The release may not list all of its assets, so page through its asset list
        # (100 per page, at most, so a shorter page is the last one).
        if page > 0 && length(assets) < 100
            break
        end
        page += 1
        assets = get_json("$(release["assets_url"])?per_page=100&page=$(page)")
    end
    throw(ArgumentError("Release '$(tag)' of $(owner)/$(repo) has no file named '$(name)'"))
end

"""
    GitHubReleaseDownloadError(url, error, api_error)

Thrown when downloading the GitHub release file `url` failed with `error`, and
downloading it through the GitHub API instead failed with `api_error`.
"""
struct GitHubReleaseDownloadError <: Exception
    url::String
    error::Any
    api_error::Any
end

function Base.showerror(io::IO, e::GitHubReleaseDownloadError)
    print(io, "GitHubReleaseDownloadError: downloading ", e.url, " failed: ")
    showerror(io, e.error)
    print(io, "\nand so did downloading it through the GitHub API: ")
    showerror(io, e.api_error)
end

# Whether `e` is a server answering a request with an HTTP error status
is_http_error(e) = e isa Downloads.RequestError && e.code == 0 && e.response.status >= 400
