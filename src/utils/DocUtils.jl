"""
    collate_markdown(
        io, inputpath, outputpath; 
        includes=String[], includename="doc_include.jl", imagesdirs=["images"]
    ) -> (pages::Vector, includes::Vector{String})

Recursively look through `inputpath` and subfolders for:
- markdown files (`.md` extension),
- code files with name matching `includename`
- folders with name in `imagesdirs`
- a text file "doc_order.txt"
and then:
- copy markdown files and folders in `imagedirs` to `outputpath`
- return a `pages::Vector` suitable to build a tree structure for `Documenter.jl`,
  where each element is either a path to a markdown file, or a pair `folder_name => Vector`,
  sorted according to "doc_order.txt" if present, or otherwise with "README.md" first and then
  in lexographical order.
- return an `includes::Vector` of code files that should be included to define modules etc 
"""
function collate_markdown(
    io, inputpath, outputpath; 
    includes=String[],
    includename="doc_include.jl", 
    imagesdirs=["images"],
    sortpref=["README.md"],
)

    docs = Any[]
    filenames_read = readdir(inputpath)

    # if a text file defining order is present, then that overrides sortpref
    if "doc_order.txt" in filenames_read
        orderpath = joinpath(inputpath, "doc_order.txt")
        sortpref = readlines(orderpath)
        println(io, "sorting in order $sortpref from file $orderpath")
    end

    # put any names in sortpref at the front of the list
    filenames_sort = String[]
    for fn in sortpref
        if fn in filenames_read
            push!(filenames_sort, fn)
        end
    end
    for fn in filenames_read
        if ! (fn in filenames_sort)
            push!(filenames_sort, fn)
        end
    end 

    for fn in filenames_sort
        inpath = joinpath(inputpath, fn)
        outpath = joinpath(outputpath, fn)
        if isdir(inpath)
            if fn in imagesdirs
                println(io, "cp $inpath --> $outpath")
                mkpath(outpath)
                cp(inpath, outpath; force=true)
            else
                subdocs, _ = collate_markdown(
                    io,
                    inpath,
                    outpath;
                    includes=includes,
                    imagesdirs=imagesdirs
                )
                !isempty(subdocs) && push!(docs, escape_markdown(fn)=>subdocs)
            end
        else
            if length(fn) >= 3 && fn[end-2:end] == ".md"
                push!(docs, joinpath(splitpath(outpath)[2:end])) # remove top level folder
                println(io, "cp $inpath --> $outpath")
                mkpath(outputpath)
                cp(inpath, outpath; force=true)
            elseif fn == includename
                push!(includes, inpath)
            end
        end
    end

    return (docs, includes)
end

function escape_markdown(str::AbstractString)
    str = replace(str, "_"=>"\\_")
    str = replace(str, "\$"=>"\\\$")
    str = replace(str, "*"=>"\\*")
    return str
end
