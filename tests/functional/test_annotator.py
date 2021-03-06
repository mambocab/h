# -*- coding: utf-8 -*-
import os

import pytest
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions
from selenium.webdriver.support.wait import WebDriverWait

from . import SeleniumTestCase, Annotator

pytestmark = pytest.mark.skipif(
    os.environ.get('TRAVIS_SECURE_ENV_VARS') == 'false',
    reason="No access to secure Travis variables.")


class TestAnnotator(SeleniumTestCase):
    def test_login(self):
        driver = self.driver
        driver.get(self.base_url + "/")

        # Assert logged in with the right username
        with Annotator(driver):
            self.register()
            self.logout()
            self.login()

            picker = (By.CLASS_NAME, 'user-picker')
            ec = expected_conditions.visibility_of_element_located(picker)
            WebDriverWait(driver, 3).until(ec)

            picker = driver.find_element_by_class_name('user-picker')
            dropdown = picker.find_element_by_class_name('dropdown-toggle')
            # Some bugs were fixed in selenium 2.35 + FF23 combo
            # Unfortunately, that means we need test both options
            try:
                assert dropdown.text == 'test'
            except AssertionError:
                assert dropdown.text == 'test/localhost'

    def test_annotation(self):
        driver = self.driver
        driver.get(self.base_url + "/")

        self.register()

        # highlight the first paragraph and click the pen to annotate it
        self.highlight("p")
        driver.find_element_by_css_selector(".annotator-adder button").click()

        # switch over to the annotator pane and click to save
        with Annotator(driver):
            annotation = driver.find_element_by_class_name('annotation')
            body = driver.switch_to_active_element()
            body.send_keys("test annotation")
            annotation.find_element_by_css_selector("button").click()

            # Wait for save
            ts = (By.TAG_NAME, "fuzzytime")
            saved = expected_conditions.visibility_of_element_located(ts)
            WebDriverWait(driver, 3).until(saved)

        def get_labels(d):
            return d.find_elements_by_css_selector(".heatmap-pointer")

        # go away and come back
        driver.get(self.base_url + "/")

        # the middle heatmap label should have a "1" in it
        WebDriverWait(driver, 30).until(lambda d: len(get_labels(d)) == 3)
        a_label = get_labels(driver)[1]
        assert a_label.text == "1"

        # if we click the heatmap we should see our annotation appear
        # make sure the username and text of the annotation are stored
        a_label.click()
        with Annotator(driver):
            annotation = (By.CLASS_NAME, 'annotation')
            ec = expected_conditions.visibility_of_element_located(annotation)
            WebDriverWait(driver, 3).until(ec)
            annotation = driver.find_element_by_class_name('annotation')
            user = annotation.find_element_by_class_name('user')
            body = annotation.find_element_by_css_selector('markdown div p')
            assert user.text == 'test'
            assert body.text == 'test annotation'
