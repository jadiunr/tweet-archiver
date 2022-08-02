# tweet-archiver

## Usage

- Please set your credentials in config.yml in advance.

```
cp config.yml.example config.yml
vim config.yml
```

```
docker run --rm -it -v $(pwd):/workdir -w /workdir perl bash
cpanm -nq Carton
carton install
carton exec perl archive.pl --target jadiunr
```
