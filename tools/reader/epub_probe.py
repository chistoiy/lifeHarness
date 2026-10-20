import zipfile, collections
paths = [
    r"C:\Users\chist\Downloads\阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ (z-library.sk, 1lib.sk, z-lib.sk).epub",
    r"C:\Users\chist\Downloads\人类简史  从动物到上帝 = Sapiens A Br_ (z-library.sk, 1lib.sk, z-lib.sk).epub",
]
for p in paths:
    z = zipfile.ZipFile(p)
    infos = z.infolist()
    cat = collections.Counter()
    sz = collections.Counter()
    for i in infos:
        e = i.filename.rsplit('.', 1)[-1].lower()
        cat[e] += 1
        sz[e] += i.file_size
    total = sum(i.file_size for i in infos)
    name = p.split('\\')[-1][:30]
    print(name, '| entries', len(infos), '| uncompressed %.1f MB' % (total / 1e6))
    print('   types:', {k: (cat[k], round(sz[k] / 1e6, 1)) for k in cat.most_common(8)})
    big = sorted(infos, key=lambda i: -i.file_size)[:5]
    print('   top5 :', [(i.filename.split('/')[-1][:34], round(i.file_size / 1e6, 2)) for i in big])
