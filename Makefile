.PHONY: all test clean mrproper

ALL=metadata.proto messaging.proto transport.proto

all: $(ALL)

TEST_DIR=./test.$(shell echo $$PPID)
test: $(ALL)
	[ ! -d $(TEST_DIR) ]
	mkdir $(TEST_DIR)
	cd $(TEST_DIR); ../examples/bluebadge > bb
	tools/amc $(TEST_DIR)/bb > $(TEST_DIR)/bb.bin

clean:
	rm -f $(ALL)

mrproper: clean
	rm -f *~
	rm -fr test.*/


%.html: %.md
	markdown $< > $@

%.proto : %.md
	./md2protobuf $< $@

