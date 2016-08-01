all:
	docker build -t builder-tmp .
	docker rm -f seafiletmp || true
	docker run -it --privileged --name seafiletmp builder-tmp bash -c 'OS=debian DIST=wheezy ARCH=i386 pbuilder --create'
	docker commit --change 'CMD ["/bin/bash"]' seafiletmp lins05/seafile-debian-builder:latest

upload:
	docker push lins05/seafile-debian-builder:latest
