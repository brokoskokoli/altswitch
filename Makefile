.PHONY: all build clean run

all: build

build:
	@chmod +x build.sh
	@./build.sh

clean:
	rm -rf AltSwitch.app

run: build
	open AltSwitch.app
