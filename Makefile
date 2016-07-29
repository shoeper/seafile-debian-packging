all:
	docker build -t lins05/seafile-debian-builder:latest .

upload:
	docker push lins05/seafile-debian-builder:latest
